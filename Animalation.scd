//***************LONG-TERM***************\\
//could do part of set with short phasing syllables. Also nature sounds. birds. whales.
//would it be possible to offer a version for grid 128 and no arc???

//clearly show how to change different options, specifically changing inputs and outputs
//indicate volume is low for headroom

//should I add recording pitch changes?



//need to provide better documentation for Parameter class

//redo length formula so it's the same length unless it goes over the end

//how can an old sample continue playing while a new one is being recorded? could rework to use BufWr with a loop and stored phasor position

//reduce maximum amplitude to allow for high resonances and four samples playing

//...there really needs to be a volume control. press both currently held parameters plus...some third thing? or how about just holding those two things?
//can't currently disable recording preset without hitting a position knob...


(

s = Server.local;

~grid128 = MonoM.new("/monome", 0);
~arc4 = Arc.new("/monome", 0);

Buffer.freeAll; //essential or buffers start piling up in RAM

SynthDef.new("Sample_Recording_Synth", {arg sample;
	var sampleInput;

	sampleInput = SoundIn.ar(0);
	RecordBuf.ar(sampleInput, sample, loop: 0, doneAction: Done.freeSelf);

}).add;

SynthDef("Sample_Length_Timer_Synth", {arg outputBus, trigger = 0;

	Out.kr(outputBus, Sweep.kr(trigger, 1));

}).add;

SynthDef("Sample_Playback_Synth", {arg rate = 0, position = 0, direction = 1, start = 0, length = 1, fmSpeed = 1, fmDepth = 0, sample, popEnvInput = 1, sampleLength, cutoff = 20000, resonance = 1, ledPhasorOutput;

	var bufrd, phasorDriver;
	var sampleLengthFrames = sampleLength * BufSampleRate.kr(sample);

	var fm = SinOsc.kr(fmSpeed, 0, fmDepth);

	phasorDriver = Phasor.ar(In.kr(position), ((rate * SinOsc.ar(fmSpeed, 0, fmDepth, 1))* direction), (sampleLengthFrames * start), sampleLengthFrames * (start + ((1 - start) * length)), sampleLengthFrames * (In.kr(position) - 1)); //position - 1 is so trigger can read a "0" position and still trigger


	bufrd = BufRd.ar(2, sample, phasorDriver, 1, 2);

	Out.ar([0, 1], In.kr(popEnvInput) * RLPF.ar(bufrd, cutoff, resonance));

	Out.kr(ledPhasorOutput, LinLin.kr(phasorDriver, start * sampleLengthFrames, sampleLengthFrames * (start + ((1 - start) * length)), 0, 16));

}).add;

SynthDef("Click_Stop_Synth", {arg outputAmplitudeBus, outputPositionBus, positionInBus;

	var ampShape = Env.new([0.05, 0, 0, 0.05], [SampleDur.ir, SampleDur.ir * 2, SampleDur.ir]);

	Out.kr(outputAmplitudeBus, EnvGen.kr(ampShape, gate: In.kr(positionInBus)));
	Out.kr(outputPositionBus, Delay2.kr(In.kr(positionInBus)));

}).add;

SynthDef("Position_Signal_Generator_Synth", {arg bus, tempPosition = 0;
	var positionSignal = SinOsc.kr(mul: 0, add: tempPosition); //constant signal generator

	Out.kr(bus, positionSignal);

}).add;

SynthDef("Position_Record_Synth", {arg inputBus, recordingBuffer;
	var recordInput;

	recordInput = In.kr(inputBus);

	RecordBuf.kr(recordInput, recordingBuffer, loop: 0, doneAction: Done.freeSelf);

}).add;

SynthDef("Position_Playback_Synth", {arg outputBus, inputBuffer, triggerRecordingLength = 0;
	var sampleLength, bufrd;
	sampleLength = triggerRecordingLength * ControlRate.ir; //WHY DIDN"T ANYONE MENTION THIS

	bufrd = BufRd.kr(1, inputBuffer, Phasor.kr(0, 1, 0, sampleLength, 0), 1, 2);

	Out.kr(outputBus, bufrd);

}).add;


s.waitForBoot({

	~grid128.usePort(15497);
	~arc4.usePort(15503);

	//variables for recording samples
	~recordingSynth = [nil, nil, nil, nil];

	~recordingStatusIndicator = [0, 0, 0, 0];
	~recordTimeBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
	~recordingLengthTimer = [nil, nil, nil, nil];

	~recordingLength = [1, 1, 1, 1];

	//variables for playing samples back
	~sampleSynth = [Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), ]; //sets maximum sample time to two minutes (120.0 seconds)

	~playbackSynth = [nil, nil, nil, nil];
	~playbackStatusIndicator = [0, 0, 0, 0];

	//variables for playback parameters

	~samplePlaybackDirection = [1, 1, 1, 1];
	~storedPlaybackRate = [1, 1, 1, 1];

	//variables for position manipulation
	~positionRecordingBuffer = [Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1), Buffer.alloc(s, s.sampleRate * 120.0, 1)]; //sets maximum position trigger recording time to two minutes (120.0 seconds)

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

	//play row led variables
	~playRowLedBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
	~currentPlayLed = [-1, -1, -1, -1]; //set to negative one so first position will be 0


	OSCFunc.newMatching(
		{ arg message, time, addr, recvPort;
			//message 1 = x axis (columns 0-15) message 2 = y axis (rows 0-7)

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

			var matrixLedLocations = [[10, 0], [11, 0], [12, 0], [10, 2], [11, 2], [12, 2], [10, 4], [11, 4], [12, 4], [10, 6], [11, 6], [12, 6]];

			if (messageThree == 1, {

				switch(~arcSelectionLeft[0], 0,{

					if(matrixIndexes[sampleNumber][messageOneOffset] == ~arcSelectionRight[1], { //if you try to select slot one where slot two already is

						~arcSelectionRight[1] = matrixIndexes[sampleNumber][(messageOneOffset + 1) % 3];

					});

					~arcSelectionLeft[0] = 1; //one means true or is held
					~arcSelectionLeft[1] = matrixIndexes[sampleNumber][messageOneOffset];

					~updateArcLeds.value(0, ~pairs[~arcSelectionLeft[1]][0].arcLedValue);
					~updateArcLeds.value(1, ~pairs[~arcSelectionLeft[1]][1].arcLedValue);

					postln("Holding Selection Left with Index " + ~arcSelectionLeft[1]);
				}, 1, {

					~arcSelectionRight[0] = 1;
					~arcSelectionRight[1] = matrixIndexes[sampleNumber][messageOneOffset];

					~updateArcLeds.value(2, ~pairs[~arcSelectionRight[1]][0].arcLedValue);
					~updateArcLeds.value(3, ~pairs[~arcSelectionRight[1]][1].arcLedValue);

					postln("Holding Selection Right with Index " + ~arcSelectionRight[1]);
				});

				for(10, 12, {arg x; //clear and reset arc selection matrix leds
					forBy(0, 6, 2, {arg y;

						~gridLeds[x + (y * 16)] = 0;

					});
				});

				//masked x + (y * width)
				~gridLeds[matrixLedLocations[~arcSelectionLeft[1]][0] + (matrixLedLocations[~arcSelectionLeft[1]][1] * 16)] = 15;
				~gridLeds[matrixLedLocations[~arcSelectionRight[1]][0] + (matrixLedLocations[~arcSelectionRight[1]][1] * 16)] = 7;
				~updateGridLeds.value;

			});

			if(messageThree == 0, {

				if(~arcSelectionLeft[0] == 1 && ~arcSelectionLeft[1] == matrixIndexes[sampleNumber][messageOneOffset], {

					~arcSelectionLeft[0] = 0;

					postln("Releasing Selection Left with Index " + ~arcSelectionLeft[1]);
				});

				if(~arcSelectionRight[0] == 1 && ~arcSelectionRight[1] == matrixIndexes[sampleNumber][messageOneOffset], {

					~arcSelectionRight[0] = 0;

					postln("Releasing Selection Right with Index" + ~arcSelectionRight[1]);
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

				~recordTimeBus[sampleNumber].get({arg index;

					~recordingLength = index;
					postln("Sample " + sampleNumber + " Length = " + index);

					~recordingSynth[sampleNumber].free;
					~recordingLengthTimer[sampleNumber].free;

					~playbackSynth[sampleNumber].set(\sampleLength, index);

				});

				~recordingStatusIndicator[sampleNumber] = 0;

				~gridLeds[15 + (ledOffsets[sampleNumber] * 16)] = 3;
				~updateGridLeds.value;

				postln("Stopping Recording of Sample " + sampleNumber);

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

			for(0, 7, {arg i;
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

				~gridLeds[13 + (ledOffsets[sampleNumber] * 16)] = 15;
				~updateGridLeds.value;

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

				~gridLeds[13 + (ledOffsets[sampleNumber] * 16)] = 0;
				~updateGridLeds.value;

				postln("Stopping Recording of Sample " + sampleNumber + " position");

			});

		});

		if(messageOne == 14 && messageThree == 1, {

			switch(~playPositionStatusIndicator[sampleNumber], 0, {

				if(~recordPostionStatusIndicator[sampleNumber] == 0, {

					~playPositionSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Position_Playback_Synth", [\outputBus, ~positionBus[sampleNumber], \inputBuffer, ~positionRecordingBuffer[sampleNumber], \triggerRecordingLength, ~recordPositionLengthTimer[sampleNumber]]);


					~playPositionStatusIndicator[sampleNumber] = 1;
					~playPositionPreSet[sampleNumber] = 0;

					~gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 15;
					~updateGridLeds.value;

					postln("Playing Position Recording on Track" + sampleNumber);
				});

				if(~recordPostionStatusIndicator[sampleNumber] == 1, {

					~playPositionPreSet[sampleNumber] = 1;

					~gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 15;
					~updateGridLeds.value;

					postln("Position Playback Pre-Set on Track" + sampleNumber);

				});
			}, 1, {

				~playPositionSynth[sampleNumber].free;
				~playPositionStatusIndicator[sampleNumber] = 0;

				~gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 0;
				~updateGridLeds.value;

				postln("Stopping Position Playback on Track " + sampleNumber);
			});

		});

	};

	~playRow = {arg sampleNumber, messageOne, messageTwo, messageThree;

		var sixteenth = 1 / 16;

		var positions = [(sixteenth * 0) + 1, (sixteenth * 1) + 1, (sixteenth * 2) + 1, (sixteenth * 3) + 1, (sixteenth * 4) + 1, (sixteenth * 5) + 1, (sixteenth * 6) + 1, (sixteenth * 7) + 1, (sixteenth * 8) + 1, (sixteenth * 9) + 1, (sixteenth * 10) + 1, (sixteenth * 11) + 1, (sixteenth * 12) + 1, (sixteenth * 13) + 1, (sixteenth * 14) + 1, (sixteenth * 15) + 1];  //plus one is to get around 0 positon not causing retrigger in sample playback

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

			var arcFunctions = {arg name, messageOne, messageTwo;
				name.change(messageTwo);
				name.sendChange;
				~updateArcLeds.value(messageOne, name.arcLedValue);
			};

			switch(message[1], 0, {

				arcFunctions.value(~pairs[~arcSelectionLeft[1]][0], 0, message[2]);

			}, 1, {

				arcFunctions.value(~pairs[~arcSelectionLeft[1]][1], 1, message[2]);

			}, 2, {

				arcFunctions.value(~pairs[~arcSelectionRight[1]][0], 2, message[2]);

			}, 3, {

				arcFunctions.value(~pairs[~arcSelectionRight[1]][1], 3, message[2]);

			});


	}, "/monome/enc/delta");

	//create playback synths

	for(0, 3, {arg sampleNumber;

		~playbackSynth[sampleNumber] = Synth("Sample_Playback_Synth", [\sample, ~sampleSynth[sampleNumber], \sampleLength, ~recordingLength, \popEnvInput, ~clickStopBus[sampleNumber][0], \position, ~clickStopBus[sampleNumber][1], \ledPhasorOutput, ~playRowLedBus[sampleNumber]]);

		~positionSynth[sampleNumber] = Synth.before(~playbackSynth[sampleNumber], "Position_Signal_Generator_Synth", [\bus, ~positionBus[sampleNumber], \tempPosition, 0]);

		~clickStopSynth[sampleNumber] = Synth.after(~positionSynth[sampleNumber], "Click_Stop_Synth", [\outputAmplitudeBus, ~clickStopBus[sampleNumber][0], \outputPositionBus, ~clickStopBus[sampleNumber][1], \positionInBus, ~positionBus[sampleNumber], \trig, 0]);

	});

	postln("Creating Sample Playback Synths 0 - 3");

	~pairs = [

		[Parameter.new("Sample Zero Cutoff", 20, 20000, 1, 2, 20000, ~playbackSynth[0], \cutoff, 0), Parameter.new("Sample Zero Resonance", 0.01, 1, 500, 1, 1, ~playbackSynth[0], \resonance, 0)], [Parameter.new("Sample Zero FM Speed", 0, 500, 5, 2, 0, ~playbackSynth[0], \fmSpeed, 0), Parameter.new("Sample Zero FM Depth", 0, 20, 25, 2, 0, ~playbackSynth[0], \fmDepth, 0)], [Parameter.new("Sample ZeroOne Loop Start", 0, 1, 100, 2, 0, ~playbackSynth[0], \start, 0), Parameter.new("Sample Zero Loop End", 0.001, 1, 100, 2, 1, ~playbackSynth[0], \length, 0)],

		[Parameter.new("Sample One Cutoff", 20, 20000, 1, 2, 20000, ~playbackSynth[1], \cutoff, 0), Parameter.new("Sample One Resonance", 0.01, 1, 500, 1, 1, ~playbackSynth[1], \resonance, 0)], [Parameter.new("Sample One FM Speed", 0, 500, 5, 2, 0, ~playbackSynth[1], \fmSpeed, 0), Parameter.new("Sample One FM Depth", 0, 20, 25, 2, 0, ~playbackSynth[1], \fmDepth, 0)], [Parameter.new("Sample One Loop Start", 0, 1, 100, 2, 0, ~playbackSynth[1], \start, 0), Parameter.new("Sample One Loop End", 0.001, 1, 100, 2, 1, ~playbackSynth[1], \length, 0)],

		[Parameter.new("Sample Two Cutoff", 20, 20000, 1, 2, 20000, ~playbackSynth[2], \cutoff, 0), Parameter.new("Sample Two Resonance", 0.01, 1, 500, 1, 1, ~playbackSynth[2], \resonance, 0)], [Parameter.new("Sample Two FM Speed", 0, 500, 5, 2, 0, ~playbackSynth[2], \fmSpeed, 0), Parameter.new("Sample Two FM Depth", 0, 20, 25, 2, 0, ~playbackSynth[2], \fmDepth, 0)], [Parameter.new("Sample Two Loop Start", 0, 1, 100, 2, 0, ~playbackSynth[2], \start, 0), Parameter.new("Sample Two Loop End", 0.001, 1, 100, 2, 1, ~playbackSynth[2], \length, 0)],

		[Parameter.new("Sample Three Cutoff", 20, 20000, 1, 2, 20000, ~playbackSynth[3], \cutoff, 0), Parameter.new("Sample Three Resonance", 0.01, 1, 500, 1, 1, ~playbackSynth[3], \resonance, 0)], [Parameter.new("Sample Three FM Speed", 0, 500, 5, 2, 0, ~playbackSynth[3], \fmSpeed, 0), Parameter.new("Sample Three FM Depth", 0, 20, 25, 2, 0, ~playbackSynth[3], \fmDepth, 0)], [Parameter.new("Sample Three Loop Start", 0, 1, 100, 2, 0, ~playbackSynth[3], \start, 0), Parameter.new("Sample Three Loop End", 0.001, 1, 100, 2, 1, ~playbackSynth[3], \length, 0)],

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

	~updateArcLeds = {arg encoderNumber, ledValue;

		var encoderTemporaryArray = Array.fill(64, { arg index;
			if(index <= ledValue, { 15 }, { 0 });
		});

		~arc4.ringmap(encoderNumber, encoderTemporaryArray);

	};


	//monitor for play row leds
	~clockDriver = Task({
		var interval = 0.01;
		var playRows = [1, 3, 5, 7];

		loop {

			for(0, 3, {arg i;

				~playRowLedBus[i].get({ arg value;

					if(value.asInteger != ~currentPlayLed[i], {
						~currentPlayLed[i] = value.asInteger;

						for(0, 15, {arg x;

							~gridLeds[x + (playRows[i] * 16)] = 1;

						});

						~gridLeds[value.asInteger + (playRows[i] * 16)] = 15;

						~updateGridLeds.value;

					});

				});

			});

			interval.yield;
		}

	});

	~clockDriver.play;

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

	~gridLeds[10 + (0 * 16)] = 15;
	~gridLeds[11 + (0 * 16)] = 7;

	//initialize arc leds

	~updateArcLeds.value(0, ~pairs[0][0].arcLedValue);
	~updateArcLeds.value(1, ~pairs[0][1].arcLedValue);
	~updateArcLeds.value(2, ~pairs[1][0].arcLedValue);
	~updateArcLeds.value(3, ~pairs[1][1].arcLedValue);

});

)