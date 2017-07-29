//need to provide better documentation for Parameter class
//could also add a table to provide more change for a higher speed

//sample start and lenght relation so no crossing...
//add arc controls, arc matrix

//led feedback
//can there be an led flashing function to show different states? (pre set)
//could put grid update things in a function...no need to have it written over and over
//inconsistencies with updating rate leds

//do sample buffers really need to be stereo?

//sample input is hard allocated to first and second inputs

//how can an old sample continue playing while a new one is being recorded? could rework to use BufWr with a loop and stored phasor position

//what the fuck is volumeAmpControl2?????

//figure out how to release memory from buffers when starting

//could do part of set with short phasing syllables. Also nature sounds. birds. whales.

//clearer variable names, clean up by using switches where appropriate

//would it be possible to offer a version for grid 128 and no arc???

//make sure to eliminate all "FAILURE IN SERVER" errors
//can't record a sample more than once

//should I add recording pitch changes?

//check all arguments in SynthDefs are still in use

//add message for stopping sample playback

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
	~recordingSynth = [nil, nil, nil, nil];

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
	~arcSelectionLeft = [0, 0]; //left is holding status (one is held 0 is not) right is selection index
	~arcSelectionRight = [0, 1];

	~gridLeds = Array.fill(128, 0);
	~arcLeds = [Array.fill(64, 0), Array.fill(64, 0), Array.fill(64, 0), Array.fill(64, 0)];

	~controlRowLedDefaultValues = [7, 3, 7, 3, 7, 3, 7, 3, 0, 3, 0, 0, 0, 3, 0, 3];


	SynthDef.new("Sample_Recording_Synth", {arg sample;
		var sampleInput;

		sampleInput = SoundIn.ar([0, 1]);
		RecordBuf.ar(sampleInput, sample, loop: 0, doneAction: Done.freeSelf);

	}).add;


	SynthDef("Sample_Length_Timer_Synth", {arg outputBus, trigger = 0;

		Out.kr(outputBus, Sweep.kr(trigger, 1));

	}).add;


	//currently starts automatically
	SynthDef("Sample_Playback_Synth", {arg rate = 0, position = 0, direction = 1, start = 0, length = 1, fmSpeed = 1, fmDepth = 0, sample, popEnvInput = 1, sampleLength, cutoff = 20000, resonance = 1;
		var bufrd, phasorDriver;
		var sampleLengthFrames = sampleLength * BufSampleRate.kr(sample);

		var fm = SinOsc.kr(fmSpeed, 0, fmDepth);

		phasorDriver = Phasor.ar(In.kr(position), (rate * direction), (sampleLengthFrames * start), sampleLengthFrames * (start + ((1 - start) * length)), sampleLengthFrames * (In.kr(position) - 1)); //position - 1 is so trigger can read a "0" position and still trigger

		bufrd = BufRd.ar(2, sample, phasorDriver, 1, 2);

		Out.ar([0, 1], In.kr(popEnvInput) * RLPF.ar(bufrd, cutoff, resonance));
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

			switch(message[2], 0, { //control rows
				~controlRow.value(0, message[1], message[2], message[3]);
			}, 2, {
				~controlRow.value(1, message[1], message[2], message[3]);
			}, 4, {
				~controlRow.value(2, message[1], message[2], message[3]);
			}, 6, {
				~controlRow.value(3, message[1], message[2], message[3]);
			}, 1, { //play rows
				~playRow.value(0, message[1], message[2], message[3]);
			}, 3, {
				~playRow.value(1, message[1], message[2], message[3]);
			}, 5, {
				~playRow.value(2, message[1], message[2], message[3]);
			}, 7, {
				~playRow.value(3, message[1], message[2], message[3]);
			});

	}, "/monome/grid/key");

	//grid row functions
	~controlRow = {arg sampleNumber, messageOne, messageTwo, messageThree;

		var rates = [0.25, 0.375, 0.5, 0.75, 1, 1.5, 2, 2.5];
		var matrixIndexes = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]];

		var ledOffsets = [0, 2, 4, 6];

		//arc matrix is 10-12
		if((messageOne == 12) || (messageOne == 11) || (messageOne == 10), {
			var messageOneOffset = messageOne - 10;

			if (messageThree == 1, {

				switch(~arcSelectionLeft[0], 0,{
					~arcSelectionLeft[0] = 1; //one means true or is held
					~arcSelectionLeft[1] = matrixIndexes[sampleNumber][messageOneOffset];

					postln("Holding One with Index " + ~arcSelectionLeft[1]);
				}, 1, {
					~arcSelectionRight[0] = 1;
					~arcSelectionRight[1] = matrixIndexes[sampleNumber][messageOneOffset];

					postln("Holding Two with Index " + ~arcSelectionRight[1]);
				});

			});

			if(messageThree == 0, {

				if(~arcSelectionLeft[0] == 1 && ~arcSelectionLeft[1] == matrixIndexes[sampleNumber][messageOneOffset], {

					~arcSelectionLeft[0] = 0;

					postln("Releasing One with Index " + ~arcSelectionLeft[1]);
				});

				if(~arcSelectionRight[0] == 1 && ~arcSelectionRight[1] == matrixIndexes[sampleNumber][messageOneOffset], {

					~arcSelectionRight[0] = 0;

					postln("Releasing Two with Index" + ~arcSelectionRight[1]);
				});

			});

		});

		if(messageOne == 15 && messageThree == 1, {

			if(~recordingStatusIndicator[sampleNumber] == 0, {

				~recordingSynth[sampleNumber] = Synth.new("Sample_Recording_Synth", [\sample, ~sampleSynth[sampleNumber]]);
				~recordingLengthTimer[sampleNumber] = Synth.after(~recordingSynth[sampleNumber], "Sample_Length_Timer_Synth", [\outputBus, ~recordTimeBus[sampleNumber], \trigger, 0]);

				~recordingStatusIndicator[sampleNumber] = 1;

				~gridLeds[15 + (ledOffsets[sampleNumber] * 16)] = 15;
				~updateGridLeds.value;

				postln("Recording Sample " + sampleNumber);
			}, {
				//playback synth is created in this function

				~playbackSynth[sampleNumber].free;
				~positionSynth[sampleNumber].free;
				~clickStopSynth[sampleNumber].free;

				~recordTimeBus[sampleNumber].get({arg index;
					var recordTime;

					recordTime = index;
					postln("Sample " + sampleNumber + " Length = " + recordTime);

					~playbackSynth[sampleNumber] = Synth("Sample_Playback_Synth", [\sample, ~sampleSynth[sampleNumber], \sampleLength, recordTime, \popEnvInput, ~clickStopBus[sampleNumber][0], \position, ~clickStopBus[sampleNumber][1]]);

					~recordingSynth[sampleNumber].free;
					~recordingLengthTimer[sampleNumber].free;

				});

				~recordingStatusIndicator[sampleNumber] = 0;

				~gridLeds[15 + (ledOffsets[sampleNumber] * 16)] = 3;
				~updateGridLeds.value;

				postln("Stopping Recording of Sample " + sampleNumber);

				~positionSynth[sampleNumber] = Synth.before(~playbackSynth[sampleNumber], "Position_Signal_Generator_Synth", [\bus, ~positionBus[sampleNumber], \tempPosition, 0]);

				~clickStopSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Click_Stop_Synth", [\outputAmplitudeBus, ~clickStopBus[sampleNumber][0], \outputPositionBus, ~clickStopBus[sampleNumber][1], \positionInBus, ~positionBus[sampleNumber], \trig, 0]);

				//postln("Creating Sample " + sampleNumber + " Playback Synth");

			});
		});


		if(messageOne == 9 && messageThree == 1, {

			if(~playbackStatusIndicator[sampleNumber] == 1, {
				~playbackSynth[sampleNumber].set(\rate, 0);

				~playbackStatusIndicator[sampleNumber] = 0;

				~gridLeds[9 + (ledOffsets[sampleNumber] * 16)] = 3;
				~updateGridLeds.value;

				postln("Stoping Playback of Sample " + sampleNumber);

			}, {
				~playbackSynth[sampleNumber].set(\rate, ~storedPlaybackRate[0]);

				~playbackStatusIndicator[sampleNumber] = 1;

				~gridLeds[9 + (ledOffsets[sampleNumber] * 16)] = 15;
				~updateGridLeds.value;

				postln("Playing Sample " + sampleNumber);
			});

		});

		if(((messageOne >= 0) && (messageOne <= 7)) && messageThree == 1, {

			if(~playbackStatusIndicator[sampleNumber] == 1, {
				~playbackSynth[sampleNumber].set(\rate, rates[messageOne]);
				~storedPlaybackRate[sampleNumber] = rates[messageOne];

			}, {
				~storedPlaybackRate[sampleNumber] = rates[messageOne]
			}
			);

			for(0, 8, {arg i;
				~gridLeds[i + (ledOffsets[sampleNumber] * 16)] = ~controlRowLedDefaultValues[i];

			});

			~gridLeds[messageOne + (ledOffsets[sampleNumber] * 16)] = 15;
			~updateGridLeds.value;

			postln("Sample " + sampleNumber + " Rate = " + rates[messageOne]);
		});

		if(messageOne == 8 && messageThree == 1, {
			~samplePlaybackDirection[sampleNumber] = ~samplePlaybackDirection[sampleNumber] * -1;

			~playbackSynth[sampleNumber].set(\direction, ~samplePlaybackDirection[sampleNumber]);

			switch(~samplePlaybackDirection[sampleNumber], 1, {

				~gridLeds[8 + (ledOffsets[sampleNumber] * 16)] = 0;
				~updateGridLeds.value;

			}, -1, {

				~gridLeds[8 + (ledOffsets[sampleNumber] * 16)] = 15;
				~updateGridLeds.value;

			});

			postln("Direction on Track " + sampleNumber + " = " + ~samplePlaybackDirection[sampleNumber]);
		});

		if(messageOne == 13 && messageThree == 1, {

			if(~recordPositionPreSet[sampleNumber] == 0, {

				~recordPositionPreSet[sampleNumber] = 1;

				postln("Record Position Pre-Set on Track " + sampleNumber);

			});

			if(~recordPostionStatusIndicator[sampleNumber] == 1, {

				~recordTimeBus[sampleNumber].get({arg index;

					~recordPositionLengthTimer[sampleNumber] = index;
					postln("Position Recording Length = " + ~recordPositionLengthTimer[sampleNumber] + " on Track " + sampleNumber);

					~recordPositionSynth[sampleNumber].free;
					~recordingLengthTimer[sampleNumber].free;

					if(~playPositionPreSet[sampleNumber] == 1, {

						~playPositionSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Position_Playback_Synth", [\outputBus, ~positionBus[sampleNumber], \inputBuffer, ~positionRecordingBuffer[sampleNumber], \triggerRecordingLength, ~recordPositionLengthTimer[sampleNumber]]);


						~playPositionStatusIndicator[sampleNumber] = 1;
						~playPositionPreSet[sampleNumber] = 0;

						postln("Playing Key Presses from a Pre-Set state on Track " + sampleNumber);

					});

				});

				~recordPostionStatusIndicator[sampleNumber] = 0;

				~recordPositionPreSet[sampleNumber] = 0;

				postln("Stopping Recording of Sample " + sampleNumber + " position");

			});

		});

		if(messageOne == 14 && messageThree == 1, {

			switch(~playPositionStatusIndicator[sampleNumber], 0, {

				if(~recordPostionStatusIndicator[sampleNumber] == 0, {

					~playPositionSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Position_Playback_Synth", [\outputBus, ~positionBus[sampleNumber], \inputBuffer, ~positionRecordingBuffer[sampleNumber], \triggerRecordingLength, ~recordPositionLengthTimer[sampleNumber]]);


					~playPositionStatusIndicator[sampleNumber] = 1;
					~playPositionPreSet[sampleNumber] = 0;

					postln("Playing Position Recording on Track" + sampleNumber);
				});

				if(~recordPostionStatusIndicator[sampleNumber] == 1, {

					~playPositionPreSet[sampleNumber] = 1;

					postln("Position Playback Pre-Set on Track" + sampleNumber);

				});
			}, 1, {

				~playPositionSynth[sampleNumber].free;
				~playPositionStatusIndicator[sampleNumber] = 0;

				postln("Stopping Position Playback on Track " + sampleNumber);
			});

		});

	};

	~playRow = {arg sampleNumber, messageOne, messageTwo, messageThree;

		var sixteenth = 1 / 16;

		var positions = [(sixteenth * 0) + 1, (sixteenth * 1) + 1, (sixteenth * 2) + 1, (sixteenth * 3) + 1, (sixteenth * 4) + 1, (sixteenth * 5) + 1, (sixteenth * 6) + 1, (sixteenth * 7) + 1, (sixteenth * 8) + 1, (sixteenth * 9) + 1, (sixteenth * 10) + 1, (sixteenth * 11) + 1, (sixteenth * 12) + 1, (sixteenth * 13) + 1, (sixteenth * 14) + 1, (sixteenth * 15) + 1];  //plus one is to get around 0 positon not triggering trig in sample play

		switch(~recordPositionPreSet[sampleNumber], 0, {

			if(messageThree == 1, {

				~positionSynth[sampleNumber].set(\tempPosition, positions[messageOne]);

				postln("Sample " + sampleNumber + " Position = " + positions[messageOne]);
			});

			if(messageThree == 0, {
				~positionSynth[sampleNumber].set(\tempPosition, 0);

				postln("Position Released on Sample" + sampleNumber);
			});

		}, 1, {

			if(~recordPostionStatusIndicator[sampleNumber] == 0, {

				~recordPositionSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Position_Record_Synth", [\inputBus, ~positionBus[sampleNumber], \recordingBuffer, ~positionRecordingBuffer[sampleNumber]]);

				~recordingLengthTimer[sampleNumber] = Synth.after(~recordPositionSynth[sampleNumber], "Sample_Length_Timer_Synth", [\outputBus, ~recordTimeBus[sampleNumber], \trigger, 0]);

				~recordPostionStatusIndicator[sampleNumber] = 1;

				postln("Recording Key Presses on Sample " + sampleNumber);

			});

			if(messageThree == 1, {

				~positionSynth[sampleNumber].set(\tempPosition, positions[messageOne]);

				postln("Sample " + sampleNumber + " Position = " + positions[messageOne]);
			});

			if(messageThree == 0, {
				~positionSynth[sampleNumber].set(\tempPosition, 0);

				postln("Position Released on Sample" + sampleNumber);
			});

		});

	};

	OSCFunc.newMatching(
		{ arg message, time, addr, recvPort;

			if(message[1] == 0, {

				~pairs[~arcSelectionLeft[1]][0].change(message[2]);
				~pairs[~arcSelectionLeft[1]][0].sendChange;
			});

			if(message[1] == 1, {

				~pairs[~arcSelectionLeft[1]][1].change(message[2]);
				~pairs[~arcSelectionLeft[1]][1].sendChange;
			});

			if(message[1] == 2, {

				~pairs[~arcSelectionRight[1]][0].change(message[2]);
				~pairs[~arcSelectionRight[1]][0].sendChange;
			});

			if(message[1] == 3, {

				~pairs[~arcSelectionRight[1]][1].change(message[2]);
				~pairs[~arcSelectionRight[1]][1].sendChange;
			});


	}, "/monome/enc/delta");

	~pairs = [

		[Parameter.new("Sample One Cutoff", 0, 20000, 1, 500, ~playbackSynth[0], \cutoff, 0), Parameter.new("Sample One Resonance", 0.01, 1, 100, 1, ~playbackSynth[0], \resonance, 0)], [Parameter.new("Sample One FM Depth", 0, 20, 100, 0, ~playbackSynth[0], \fmDepth, 0), Parameter.new("Sample One FM Speed", 0, 500, 2, 0, ~playbackSynth[0], \fmSpeed, 0)], [Parameter.new("Sample One Loop Start", 0, 1, 500, 0, ~playbackSynth[0], \start, 0), Parameter.new("Sample One Loop End", 0, 1, 500, 1, ~playbackSynth[0], \length, 0)],

		[Parameter.new("Sample Two Cutoff", 0, 20000, 1, 500, ~playbackSynth[1], \cutoff, 0), Parameter.new("Sample Two Resonance", 0.01, 1, 100, 1, ~playbackSynth[1], \resonance, 0)], [Parameter.new("Sample Two FM Depth", 0, 20, 100, 0, ~playbackSynth[1], \fmDepth, 0), Parameter.new("Sample Two FM Speed", 0, 500, 2, 0, ~playbackSynth[1], \fmSpeed, 0)], [Parameter.new("Sample Two Loop Start", 0, 1, 500, 0, ~playbackSynth[1], \start, 0), Parameter.new("Sample Two Loop End", 0, 1, 500, 1, ~playbackSynth[1], \length, 0)],

		[Parameter.new("Sample Three Cutoff", 0, 20000, 1, 500, ~playbackSynth[2], \cutoff, 0), Parameter.new("Sample Three Resonance", 0.01, 1, 100, 1, ~playbackSynth[2], \resonance, 0)], [Parameter.new("Sample Three FM Depth", 0, 20, 100, 0, ~playbackSynth[2], \fmDepth, 0), Parameter.new("Sample Three FM Speed", 0, 500, 2, 0, ~playbackSynth[2], \fmSpeed, 0)], [Parameter.new("Sample Three Loop Start", 0, 1, 500, 0, ~playbackSynth[2], \start, 0), Parameter.new("Sample Three Loop End", 0, 1, 500, 1, ~playbackSynth[2], \length, 0)],

		[Parameter.new("Sample Four Cutoff", 0, 20000, 1, 500, ~playbackSynth[3], \cutoff, 0), Parameter.new("Sample Four Resonance", 0.01, 1, 100, 1, ~playbackSynth[3], \resonance, 0)], [Parameter.new("Sample Four FM Depth", 0, 20, 100, 0, ~playbackSynth[3], \fmDepth, 0), Parameter.new("Sample Four FM Speed", 0, 500, 2, 0, ~playbackSynth[3], \fmSpeed, 0)], [Parameter.new("Sample Four Loop Start", 0, 1, 500, 0, ~playbackSynth[3], \start, 0), Parameter.new("Sample Four Loop End", 0, 1, 500, 1, ~playbackSynth[3], \length, 0)],

	];

	~updateGridLeds = {

		var x, y, tempGridLedsLeft, tempGridLedsRight, gridWidth;

		gridWidth = 16;

		tempGridLedsLeft = Array.fill(64, 0);
		tempGridLedsRight = Array.fill(64, 0);

		for(0, 7, { arg y;
			for(0, 15, { arg x;

				var index16 = x + (y * gridWidth);
				var index8 = x + (y * 8);

				if(x < 8, {
					tempGridLedsLeft[index8] = ~gridLeds[index16];
				}, {
					tempGridLedsRight[index8 - 8] = ~gridLeds[index16];
				});

			});
		});

		~grid128.levmap(0, 0, tempGridLedsLeft);
		~grid128.levmap(8, 0, tempGridLedsRight);

	};

	~updateArcLeds = {

	};

	//initialize control row leds

	forBy(0, 6, 2, {arg y;
		for(0, 15, {arg x;

			~grid128.levset(x, y, ~controlRowLedDefaultValues[x]);
			~gridLeds[x + (y * 16)] = ~controlRowLedDefaultValues[x];



		});
		//initialize rate led to speed 1 (column 4)
		~grid128.levset(4, y, 15);
		~gridLeds[4 + (y * 16)] = 15;

	});



});

)

~updateGridLeds.value;
~grid128.levall(0);

s.reboot

s.queryAllNodes