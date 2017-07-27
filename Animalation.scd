//need to provide better documentation for Parameter class

//sample start and lenght relation so no crossing...
//add arc controls, arc matrix
//led feedback (possibly consider a system where all grid buttons are converted to x + (y * width) and sorted by 0-32 being sample one controls 33-64 sample two etc.


//add feature to begin recording key presses with first key press, also preselect playing
//also add variable length trigger buffers


//maybe avoid camel case synth definition names?????? to avoid confusion with variables

//do sample buffers really need to be stereo?

//sample input is hard allocated to first and second inputs

//how can an old sample continue playing while a new one is being recorded?

//what the fuck is volumeAmpControl2?????

//figure out how to release memory from buffers when starting

//could do part of set with short phasing syllables. Also nature sounds. birds. whales.


(

s = Server.local;

~grid128 = MonoM.new("/monome", 0);
~arc4 = Arc.new("/monome", 0);


s.waitForBoot({

	~grid128.usePort(15497);
	~arc4.usePort(15503);

	~count = -1;

	~recordingIndicator = [0, 0, 0, 0];

	~recordingTriggerIndicator = [0, 0, 0, 0];
	~recordTimeBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
	~recordTriggerTime = [0, 0, 0, 0];

	~recording = [nil, nil, nil, nil];
	~timer = [nil, nil, nil, nil];

	~playbackIndicator = [0, 0, 0, 0];
	~direction = [1, 1, 1, 1];
	~storedRate = [1, 1, 1, 1];

	~loopStartPosition = [0, 0, 0, 0];
	~loopEndPosition = [1, 1, 1, 1];

	~playback = [nil, nil, nil, nil];
	~position = [nil, nil, nil, nil];

	~recordPosition = [nil, nil, nil, nil];
	~playPosition = [nil, nil, nil, nil];

	//could these busses be allocated in another way that is less verbose?
	~positionBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
	~popBus = [[Bus.control(s, 1), Bus.control(s, 1)] , [Bus.control(s, 1), Bus.control(s, 1)] , [Bus.control(s, 1), Bus.control(s, 1)] , [Bus.control(s, 1), Bus.control(s, 1)]];

	~popSynthVariable = [nil, nil, nil, nil];

	~sample = [Buffer.alloc(s, s.sampleRate * 120.0, 2), Buffer.alloc(s, s.sampleRate * 120.0, 2), Buffer.alloc(s, s.sampleRate * 120.0, 2), Buffer.alloc(s, s.sampleRate * 120.0, 2), ];

	~positionBuffer = [Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1)];

	//~restartTriggerBus = [nil, nil, nil, nil];
	~triggerPlaybackIndicator = [0, 0, 0, 0];

	~matrixOneHeld = [0, 10];
	~matrixTwoPressed = [0, 0];


	SynthDef.new("recordSample", {arg sample;
		var sampleInput;

		sampleInput = SoundIn.ar([0, 1]);
		RecordBuf.ar(sampleInput, sample, loop: 0, doneAction: Done.freeSelf);

	}).add;


	SynthDef("Recording Timer", {arg outputBus, trigger = 0;

		Out.kr(outputBus, Sweep.kr(trigger, 1));

	}).add;


	//currently starts automatically
	SynthDef("playSample", {arg rate = 0, position = 0, direction = 1, start = 0, length = 1, fmSpeed = 1, fmDepth = 0, sample, popEnvInput = 1, sampleLength;
		var bufrd, phasorDriver;
		var sampleLengthFrames = sampleLength * BufSampleRate.kr(sample);

		//phasorDriver = Phasor.ar(In.kr(position), (BufRateScale.kr(sample) * (rate * direction)) * SinOsc.kr(fmSpeed, 1.5pi, fmDepth, 1), BufFrames.kr(sample) * start, BufFrames.kr(sample) * (start + ((1 - start) * length)), BufFrames.kr(sample) * (In.kr(position) - 1));

		phasorDriver = Phasor.ar(In.kr(position), (rate * direction), (sampleLengthFrames * start), sampleLengthFrames * (start + ((1 - start) * length)), sampleLengthFrames * (In.kr(position) - 1));

		//could seperate this into variables to make it more readable
		bufrd = BufRd.ar(2, sample, phasorDriver, 1, 2);
		//position - 1 is so trigger can read a "0" position and still trigger


		Out.ar([0, 1], In.kr(popEnvInput) * bufrd);
	}).add;



	SynthDef("Pop Stop Synth", {arg outputAmplitudeBus, outputPositionBus, positionInBus; //should be created after "positionBus"

		var ampShape = Env.new([1, 0, 0, 1], [SampleDur.ir, SampleDur.ir * 2, SampleDur.ir]);

		Out.kr(outputAmplitudeBus, EnvGen.kr(ampShape, gate: In.kr(positionInBus)));
		Out.kr(outputPositionBus, Delay2.kr(In.kr(positionInBus)));

	}).add;



	SynthDef("positionBus", {arg bus, tempPosition = 0; //should output to Pop Stop Synth
		var positionSignal = SinOsc.kr(mul: 0, add: tempPosition); //constant signal generator

		Out.kr(bus, positionSignal);

	}).add;

	//this buffer is recording longer than it is allocated to do so
	//also it won't free when done...because it seems to record indefinitly
	SynthDef("recordPosition", {arg inputBus, recordingBuffer;
		var recordInput;

		recordInput = In.kr(inputBus);

		RecordBuf.kr(recordInput, recordingBuffer, loop: 0, doneAction: Done.freeSelf);

	}).add;

	SynthDef("playPosition", {arg outputBus, inputBuffer, triggerRecordingLength = 0;
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

			if(~recordingIndicator[sampleNumber] == 0, {

				~recording[sampleNumber] = Synth.new("recordSample", [\sample, ~sample[sampleNumber]]);
				~timer[sampleNumber] = Synth.after(~recording[sampleNumber], "Recording Timer", [\outputBus, ~recordTimeBus[sampleNumber], \trigger, 0]);

				~recordingIndicator[sampleNumber] = 1;

				postln("Recording Sample One!");
			}, {
				//playback synth is created in this function

				~playback[sampleNumber].free;
				~position[sampleNumber].free;
				~popSynthVariable[sampleNumber].free;

				~recordTimeBus[sampleNumber].get({arg index;
					var recordTime;

					recordTime = index;
					postln("Sample Length = " + recordTime);

					~playback[sampleNumber] = Synth("playSample", [\sample, ~sample[sampleNumber], \sampleLength, recordTime, \popEnvInput, ~popBus[sampleNumber][0], \position, ~popBus[sampleNumber][1]]);

					~recording[sampleNumber].free;
					~timer[sampleNumber].free;

				});

				~recordingIndicator[sampleNumber] = 0;

				postln("Stopping Recording of Sample One!");

				~position[sampleNumber] = Synth.before(~playback[sampleNumber], "positionBus", [\bus, ~positionBus[sampleNumber], \tempPosition, 0]);

				~popSynthVariable[sampleNumber] = Synth.after(~position[sampleNumber], "Pop Stop Synth", [\outputAmplitudeBus, ~popBus[sampleNumber][0], \outputPositionBus, ~popBus[sampleNumber][1], \positionInBus, ~positionBus[sampleNumber], \trig, 0]);

				postln("Creating Sample One Player!");

			});
		});

		if(messageOne == 15 && messageThree == 0, {


		});

		if(messageOne == 9 && messageThree == 1, {

			if(~playbackIndicator[sampleNumber] == 1, {
				~playback[sampleNumber].set(\rate, 0);

				~playbackIndicator[sampleNumber] = 0;

			}, {
				~playback[sampleNumber].set(\rate, ~storedRate[0]);

				~playbackIndicator[sampleNumber] = 1;
			});

			postln("Playing Sample One");
		});

		if(((messageOne >= 0) && (messageOne <= 7)) && messageThree == 1, {

			if(~playbackIndicator[sampleNumber] == 1, {
				~playback[sampleNumber].set(\rate, rates[messageOne]);
				~storedRate[sampleNumber] = rates[messageOne];
			}, {
				~storedRate[sampleNumber] = rates[messageOne]
			}
			);

			postln("Sample One Rate = " + rates[messageOne]);
		});

		if(messageOne == 8 && messageThree == 1, {
			~direction[sampleNumber] = ~direction[sampleNumber] * -1;

			~playback[sampleNumber].set(\direction, ~direction[sampleNumber]);

			postln("Direction = " + ~direction[sampleNumber]);
		});

		if(messageOne == 13 && messageThree == 1, {

			if(~recordingTriggerIndicator[sampleNumber] == 0, {

				~recordPosition[sampleNumber] = Synth.after(~position[sampleNumber], "recordPosition", [\inputBus, ~positionBus[sampleNumber], \recordingBuffer, ~positionBuffer[sampleNumber]]);

				~timer[sampleNumber] = Synth.after(~recordPosition[sampleNumber], "Recording Timer", [\outputBus, ~recordTimeBus[sampleNumber], \trigger, 0]);

				~recordingTriggerIndicator[sampleNumber] = 1;

				postln("Recording Key Presses on Sample " + sampleNumber);

			}, {

				~recordTimeBus[sampleNumber].get({arg index;

					~recordTriggerTime[sampleNumber] = index;
					postln("Trigger Recording Length = " + ~recordTriggerTime[sampleNumber]);

					~recordPosition[sampleNumber].free;
					~timer[sampleNumber].free;

				});

				~recordingTriggerIndicator[sampleNumber] = 0;

				postln("Stopping Recording of Sample " + sampleNumber + " triggers");

			});
		});

		if(messageOne == 14 && messageThree == 1, {

			if(~triggerPlaybackIndicator[sampleNumber] == 0, {

				~playPosition[sampleNumber] = Synth.after(~position[sampleNumber], "playPosition", [\outputBus, ~positionBus[sampleNumber], \inputBuffer, ~positionBuffer[sampleNumber], \triggerRecordingLength, ~recordTriggerTime[sampleNumber]]);


				~triggerPlaybackIndicator[sampleNumber] = 1;

				postln("Playing Key Presses");
			}, {
				~playPosition[sampleNumber].free;
				~triggerPlaybackIndicator[sampleNumber] = 0;

				postln("Stopping Key Presses");
			});

		});

	};

	~playRow = {arg sampleNumber, messageOne, messageTwo, messageThree;

		var sixteenth = 1 / 16;

		var positions = [(sixteenth * 0) + 1, (sixteenth * 1) + 1, (sixteenth * 2) + 1, (sixteenth * 3) + 1, (sixteenth * 4) + 1, (sixteenth * 5) + 1, (sixteenth * 6) + 1, (sixteenth * 7) + 1, (sixteenth * 8) + 1, (sixteenth * 9) + 1, (sixteenth * 10) + 1, (sixteenth * 11) + 1, (sixteenth * 12) + 1, (sixteenth * 13) + 1, (sixteenth * 14) + 1, (sixteenth * 15) + 1];  //plus one is to get around 0 positon not triggering trig in sample play

		if(messageThree == 1, {

			~position[sampleNumber].set(\tempPosition, positions[messageOne]);

			postln("Sample One Position = " + positions[messageOne]);
		});

		if(messageThree == 0, {
			~position[sampleNumber].set(\tempPosition, 0);

			postln("Sample One Position = 0");
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

	~pairs = [[Parameter("Sample One FM Depth", 0, 20, 100, 0, ~playback[0], \fmDepth, 0), Parameter("Sample One FM Speed", 0, 500, 2, 0, ~playback[0], \fmSpeed, 0)], [Parameter("Sample One Loop Start", 0, 1, 500, 0, ~playback[0], \start, 0), Parameter("Sample One Loop End", 0, 1, 500, 1, ~playback[0], \length, 0)]];

});

)

s.reboot

s.queryAllNodes


{ ~recordTriggerTime[0] }.value