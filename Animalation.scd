//need to provide better documentation for Parameter class

//sample start and lenght relation so no crossing...
//add arc controls, arc matrix
//led feedback (possibly consider a system where all grid buttons are converted to x + (y * width) and sorted by 0-32 being sample one controls 33-64 sample two etc.

//do sample buffers really need to be stereo?

//sample input is hard allocated to first and second inputs

//how can an old sample continue playing while a new one is being recorded?

//what the fuck is volumeAmpControl2?????

//figure out how to release memory from buffers when starting

//could do part of set with short phasing syllables. Also nature sounds. birds. whales.

//clearer variable names, clean up by using switches where appropriate

//would it be possible to offer a version for grid 128 and no arc???

//make sure to eliminate all "FAILURE IN SERVER" errors
//can't record a sample more than once


(

s = Server.local;

~grid128 = MonoM.new("/monome", 0);
~arc4 = Arc.new("/monome", 0);

Buffer.freeAll; //essential or buffers start piling up in RAM


s.waitForBoot({

	~grid128.usePort(15497);
	~arc4.usePort(15503);

	~count = -1;

	//variables for recording samples
	~recordingSynth = [nil, nil, nil, nil]; //what the hell is this? variable name too unclear

	~recordingStatusIndicator = [0, 0, 0, 0];
	~recordTimeBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
	~recordingLengthTimer = [nil, nil, nil, nil];

	//variables for playing samples back
	~sampleSynth = [Buffer.alloc(s, s.sampleRate * 120.0, 2), Buffer.alloc(s, s.sampleRate * 120.0, 2), Buffer.alloc(s, s.sampleRate * 120.0, 2), Buffer.alloc(s, s.sampleRate * 120.0, 2), ];

	~playbackSynth = [nil, nil, nil, nil];
~playbackStatusIndicator = [0, 0, 0, 0];

	//variables for playback parameters

	~samplePlaybackDirection = [1, 1, 1, 1];
	~storedPlaybackRate = [1, 1, 1, 1];

	//variables for position manipulation
	~positionRecordingBuffer = [Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1)];

	~positionSynth = [nil, nil, nil, nil];

	//could these busses be allocated in another way that is less verbose?
	~positionBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];

	~clickStopSynth = [nil, nil, nil, nil];

	~clickStopBus = [[Bus.control(s, 1), Bus.control(s, 1)] , [Bus.control(s, 1), Bus.control(s, 1)] , [Bus.control(s, 1), Bus.control(s, 1)] , [Bus.control(s, 1), Bus.control(s, 1)]]; //I don't think I need eight, just four

	//variables for recording key triggers
	~recordPositionSynth = [nil, nil, nil, nil];

	~recordPositionPreSet = [0, 0, 0, 0];
	~recordPostionStatusIndicator = [0, 0, 0, 0];
	~recordPositionLengthTimer = [0, 0, 0, 0];

	//variables for playing back key triggeres
	~playPositionSynth = [nil, nil, nil, nil];

	~playPositionPreSet = [0, 0, 0, 0];

	~playPositionStatusIndicator = [0, 0, 0, 0];



//variables for arc parameters
	~loopStartPosition = [0, 0, 0, 0];
	~loopEndPosition = [1, 1, 1, 1];

//variables for matrix selection
	~matrixOneHeld = [0, 10];
	~matrixTwoPressed = [0, 0];


	SynthDef.new("Sample_Recording_Synth", {arg sample;
		var sampleInput;

		sampleInput = SoundIn.ar([0, 1]);
		RecordBuf.ar(sampleInput, sample, loop: 0, doneAction: Done.freeSelf);

	}).add;


	SynthDef("Sample_Length_Timer_Synth", {arg outputBus, trigger = 0;

		Out.kr(outputBus, Sweep.kr(trigger, 1));

	}).add;


	//currently starts automatically
	SynthDef("Sample_Playback_Synth", {arg rate = 0, position = 0, direction = 1, start = 0, length = 1, fmSpeed = 1, fmDepth = 0, sample, popEnvInput = 1, sampleLength;
		var bufrd, phasorDriver;
		var sampleLengthFrames = sampleLength * BufSampleRate.kr(sample);

		//phasorDriver = Phasor.ar(In.kr(position), (BufRateScale.kr(sample) * (rate * direction)) * SinOsc.kr(fmSpeed, 1.5pi, fmDepth, 1), BufFrames.kr(sample) * start, BufFrames.kr(sample) * (start + ((1 - start) * length)), BufFrames.kr(sample) * (In.kr(position) - 1));

		phasorDriver = Phasor.ar(In.kr(position), (rate * direction), (sampleLengthFrames * start), sampleLengthFrames * (start + ((1 - start) * length)), sampleLengthFrames * (In.kr(position) - 1));

		//could seperate this into variables to make it more readable
		bufrd = BufRd.ar(2, sample, phasorDriver, 1, 2);
		//position - 1 is so trigger can read a "0" position and still trigger


		Out.ar([0, 1], In.kr(popEnvInput) * bufrd);
	}).add;



	SynthDef("Click_Stop_Synth", {arg outputAmplitudeBus, outputPositionBus, positionInBus; //should be created after "Position_Signal_Generator_Synth"

		var ampShape = Env.new([1, 0, 0, 1], [SampleDur.ir, SampleDur.ir * 2, SampleDur.ir]);

		Out.kr(outputAmplitudeBus, EnvGen.kr(ampShape, gate: In.kr(positionInBus)));
		Out.kr(outputPositionBus, Delay2.kr(In.kr(positionInBus)));

	}).add;



	SynthDef("Position_Signal_Generator_Synth", {arg bus, tempPosition = 0; //should output to Click_Stop_Synth
		var positionSignal = SinOsc.kr(mul: 0, add: tempPosition); //constant signal generator

		Out.kr(bus, positionSignal);

	}).add;

	//this buffer is recording longer than it is allocated to do so
	//also it won't free when done...because it seems to record indefinitly
	SynthDef("Position_Record_Synth", {arg inputBus, recordingBuffer;
		var recordInput;

		recordInput = In.kr(inputBus);

		RecordBuf.kr(recordInput, recordingBuffer, loop: 0, doneAction: Done.freeSelf);

	}).add;

	SynthDef("Position_Playback_Synth", {arg outputBus, inputBuffer, triggerRecordingLength = 0;
		var sampleLength, bufrd;
		//var playingPosition = PlayBuf.kr(1, inputBuffer, 1, loop: 1, doneAction: Done.freeSelf);
		sampleLength = triggerRecordingLength * ControlRate.ir; //WHY DIDN"T ANYONE MENTION THIS

		bufrd = BufRd.kr(1, inputBuffer, Phasor.kr(0, 1, 0, sampleLength, 0), 1, 2);

		Out.kr(outputBus, bufrd);

	}).add;


	~clockDriver = Task({
		var interval = 0.25;

		loop {
			~count = (~count + 1) % 16;
			//postln(~count);

			interval.yield;
		}

	});

	~clockDriver.play;

	OSCFunc.newMatching(
		{ arg message, time, addr, recvPort;
			//message 1 = x axis (rows 0-15) message 2 = y axis (columns 0-7)


			~grid128.ledset(message[1], message[2], message[3]);

			//control rows

			if(message[2] == 0, {

				~controlRow.value(0, message[1], message[2], message[3]);

			});

			if(message[2] == 2, {

				~controlRow.value(1, message[1], message[2], message[3]);

			});

			if(message[2] == 4, {

				~controlRow.value(2, message[1], message[2], message[3]);

			});

			if(message[2] == 6, {

				~controlRow.value(3, message[1], message[2], message[3]);

			});

			//play rows

			if(message[2] == 1, {

				~playRow.value(0, message[1], message[2], message[3]);

			});

			if(message[2] == 3, {

				~playRow.value(1, message[1], message[2], message[3]);

			});

			if(message[2] == 5, {

				~playRow.value(2, message[1], message[2], message[3]);

			});

			if(message[2] == 7, {

				~playRow.value(3, message[1], message[2], message[3]);

			});

	}, "/monome/grid/key");

	//grid row functions
	~controlRow = {arg sampleNumber, messageOne, messageTwo, messageThree;

		var rates = [0.25, 0.375, 0.5, 0.75, 1, 1.5, 2, 2.5];

		//arc matrix is 10-12
		if((messageOne == 12) || (messageOne == 11) || (messageOne == 10), {

			if (messageThree == 1, {

				if(~matrixOneHeld[0] == 0,{
					~matrixOneHeld[0] = 1;
					~matrixOneHeld[1] = messageOne;

					postln("Holding One");
				});

				if(~matrixOneHeld[0] == 1 && ~matrixOneHeld[1] != messageOne, {
					~matrixTwoPressed[0] = 1;
					~matrixTwoPressed[1] = messageOne;

					postln("Holding Two");
				});

			});

			if(messageThree == 0, {

				if(~matrixOneHeld[0] == 1 && ~matrixOneHeld[1] == messageOne, {

					~matrixOneHeld[0] = 0;
					~matrixOneHeld[1] = 0;

					postln("Releasing One");
				});

				if(~matrixTwoPressed[0] == 1 && ~matrixTwoPressed[1] == messageOne, {

					~matrixTwoPressed[0] = 0;
					~matrixTwoPressed[1] = 0;

					postln("Releasing Two");
				});

			});

		});

		if(messageOne == 15 && messageThree == 1, {

			if(~recordingStatusIndicator[sampleNumber] == 0, {

				~recordingSynth[sampleNumber] = Synth.new("Sample_Recording_Synth", [\sample, ~sampleSynth[sampleNumber]]);
				~recordingLengthTimer[sampleNumber] = Synth.after(~recordingSynth[sampleNumber], "Sample_Length_Timer_Synth", [\outputBus, ~recordTimeBus[sampleNumber], \trigger, 0]);

				~recordingStatusIndicator[sampleNumber] = 1;

				postln("Recording Sample One!");
			}, {
				//playback synth is created in this function

				~playbackSynth[sampleNumber].free;
				~positionSynth[sampleNumber].free;
				~clickStopSynth[sampleNumber].free;

				~recordTimeBus[sampleNumber].get({arg index;
					var recordTime;

					recordTime = index;
					postln("Sample Length = " + recordTime);

					~playbackSynth[sampleNumber] = Synth("Sample_Playback_Synth", [\sample, ~sampleSynth[sampleNumber], \sampleLength, recordTime, \popEnvInput, ~clickStopBus[sampleNumber][0], \position, ~clickStopBus[sampleNumber][1]]);

					~recordingSynth[sampleNumber].free;
					~recordingLengthTimer[sampleNumber].free;

				});

				~recordingStatusIndicator[sampleNumber] = 0;

				postln("Stopping Recording of Sample One!");

				~positionSynth[sampleNumber] = Synth.before(~playbackSynth[sampleNumber], "Position_Signal_Generator_Synth", [\bus, ~positionBus[sampleNumber], \tempPosition, 0]);

				~clickStopSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Click_Stop_Synth", [\outputAmplitudeBus, ~clickStopBus[sampleNumber][0], \outputPositionBus, ~clickStopBus[sampleNumber][1], \positionInBus, ~positionBus[sampleNumber], \trig, 0]);

				postln("Creating Sample One Player!");

			});
		});

		if(messageOne == 15 && messageThree == 0, {


		});

		if(messageOne == 9 && messageThree == 1, {

			if(~playbackStatusIndicator[sampleNumber] == 1, {
				~playbackSynth[sampleNumber].set(\rate, 0);

				~playbackStatusIndicator[sampleNumber] = 0;

			}, {
				~playbackSynth[sampleNumber].set(\rate, ~storedPlaybackRate[0]);

				~playbackStatusIndicator[sampleNumber] = 1;
			});

			postln("Playing Sample One");
		});

		if(((messageOne >= 0) && (messageOne <= 7)) && messageThree == 1, {

			if(~playbackStatusIndicator[sampleNumber] == 1, {
				~playbackSynth[sampleNumber].set(\rate, rates[messageOne]);
				~storedPlaybackRate[sampleNumber] = rates[messageOne];
			}, {
				~storedPlaybackRate[sampleNumber] = rates[messageOne]
			}
			);

			postln("Sample One Rate = " + rates[messageOne]);
		});

		if(messageOne == 8 && messageThree == 1, {
			~samplePlaybackDirection[sampleNumber] = ~samplePlaybackDirection[sampleNumber] * -1;

			~playbackSynth[sampleNumber].set(\direction, ~samplePlaybackDirection[sampleNumber]);

			postln("Direction = " + ~samplePlaybackDirection[sampleNumber]);
		});

		if(messageOne == 13 && messageThree == 1, {

			if(~recordPositionPreSet[sampleNumber] == 0, {

				~recordPositionPreSet[sampleNumber] = 1;

				post("Record Trigger Set!!!");

			});

			if(~recordPostionStatusIndicator[sampleNumber] == 1, {

				~recordTimeBus[sampleNumber].get({arg index;

					~recordPositionLengthTimer[sampleNumber] = index;
					postln("Trigger Recording Length = " + ~recordPositionLengthTimer[sampleNumber]);

					~recordPositionSynth[sampleNumber].free;
					~recordingLengthTimer[sampleNumber].free;

					if(~playPositionPreSet[sampleNumber] == 1, {

						~playPositionSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Position_Playback_Synth", [\outputBus, ~positionBus[sampleNumber], \inputBuffer, ~positionRecordingBuffer[sampleNumber], \triggerRecordingLength, ~recordPositionLengthTimer[sampleNumber]]);


						~playPositionStatusIndicator[sampleNumber] = 1;
						~playPositionPreSet[sampleNumber] = 0;

						postln("Playing Key Presses from Pre-Select");

					});

				});

				~recordPostionStatusIndicator[sampleNumber] = 0;

				~recordPositionPreSet[sampleNumber] = 0;

				postln("Stopping Recording of Sample " + sampleNumber + " triggers");

			});

			////////////////////////////////////////////////////////////////////////

			////////////////////////////////////////////////////////////////////////
		});

		if(messageOne == 14 && messageThree == 1, {

			switch(~playPositionStatusIndicator[sampleNumber], 0, {

				if(~recordPostionStatusIndicator[sampleNumber] == 0, {

					~playPositionSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Position_Playback_Synth", [\outputBus, ~positionBus[sampleNumber], \inputBuffer, ~positionRecordingBuffer[sampleNumber], \triggerRecordingLength, ~recordPositionLengthTimer[sampleNumber]]);


					~playPositionStatusIndicator[sampleNumber] = 1;
					~playPositionPreSet[sampleNumber] = 0; //added [sampleNumber without checking in VIM

					postln("Playing Key Presses");
				});

				if(~recordPostionStatusIndicator[sampleNumber] == 1, {

					~playPositionPreSet[sampleNumber] = 1;

					postln("Key Press Playing READY!");

				});
			}, 1, { //second case for switch

				~playPositionSynth[sampleNumber].free;
				~playPositionStatusIndicator[sampleNumber] = 0;

				postln("Stopping Key Presses");
			});

		});

	};

	~playRow = {arg sampleNumber, messageOne, messageTwo, messageThree;

		var sixteenth = 1 / 16;

		var positions = [(sixteenth * 0) + 1, (sixteenth * 1) + 1, (sixteenth * 2) + 1, (sixteenth * 3) + 1, (sixteenth * 4) + 1, (sixteenth * 5) + 1, (sixteenth * 6) + 1, (sixteenth * 7) + 1, (sixteenth * 8) + 1, (sixteenth * 9) + 1, (sixteenth * 10) + 1, (sixteenth * 11) + 1, (sixteenth * 12) + 1, (sixteenth * 13) + 1, (sixteenth * 14) + 1, (sixteenth * 15) + 1];  //plus one is to get around 0 positon not triggering trig in sample play

		switch(~recordPositionPreSet[sampleNumber], 0, {

			if(messageThree == 1, {

				~positionSynth[sampleNumber].set(\tempPosition, positions[messageOne]);

				postln("Sample One Position = " + positions[messageOne]);
			});

			if(messageThree == 0, {
				~positionSynth[sampleNumber].set(\tempPosition, 0);

				postln("Sample One Position = 0");
			});

		}, 1, {
			/////////////////////////////////////////
			if(~recordPostionStatusIndicator[sampleNumber] == 0, {

				~recordPositionSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Position_Record_Synth", [\inputBus, ~positionBus[sampleNumber], \recordingBuffer, ~positionRecordingBuffer[sampleNumber]]);

				~recordingLengthTimer[sampleNumber] = Synth.after(~recordPositionSynth[sampleNumber], "Sample_Length_Timer_Synth", [\outputBus, ~recordTimeBus[sampleNumber], \trigger, 0]);

				~recordPostionStatusIndicator[sampleNumber] = 1;

				postln("Recording Key Presses on Sample " + sampleNumber);

			});
			//////////////////////////////////

			if(messageThree == 1, {

				~positionSynth[sampleNumber].set(\tempPosition, positions[messageOne]);

				postln("Sample One Position = " + positions[messageOne]);
			});

			if(messageThree == 0, {
				~positionSynth[sampleNumber].set(\tempPosition, 0);

				postln("Sample One Position = 0");
			});

		});

	};

	OSCFunc.newMatching(
		{ arg message, time, addr, recvPort;

			if(message[1] == 0, {

				//I believe selection goes in first index: ~pairs[selection][0]...
				~pairs[0][0].change(message[2]);
				~pairs[0][0].sendChange;
			});

			if(message[1] == 1, {

				~pairs[0][1].change(message[2]);
				~pairs[0][1].sendChange;
			});

			if(message[1] == 2, {

				~pairs[1][0].change(message[2]);
				~pairs[1][0].sendChange;
			});

			if(message[1] == 3, {

				~pairs[1][1].change(message[2]);
				~pairs[1][1].sendChange;
			});


	}, "/monome/enc/delta");

	~pairs = [[Parameter("Sample One FM Depth", 0, 20, 100, 0, ~playbackSynth[0], \fmDepth, 0), Parameter("Sample One FM Speed", 0, 500, 2, 0, ~playbackSynth[0], \fmSpeed, 0)], [Parameter("Sample One Loop Start", 0, 1, 500, 0, ~playbackSynth[0], \start, 0), Parameter("Sample One Loop End", 0, 1, 500, 1, ~playbackSynth[0], \length, 0)]];

});

)

s.reboot

s.queryAllNodes


