s.boot; //press ctrl+enter here first, or hit ctrl+b, or go to server > boot server
(
//*************************************************\\

// ESSENTIAL TO MAKE YOUR GRID AND ARC WORK WITH THIS PROGRAM:
// enter the numbers you see in the post window after "Device connected on port: " for both your grid 128 and your arc

var gridDevicePort = 14661;
var arcDevicePort = 17268; //set this option to 'nil' to use Animalation without an arc 4

//  USER OPTIONS AREA  \\

// audio inputs and outputs start counting from 0 (input 1 on your interface is 0, input 2 is 1 etc.)
var audioInput = 0;
var inputHPFfrequency = 100; //sets frequency of HPF on input

var maxRecordingLength = 120; // the maximum number of seconds you can record one sample
var audioOutput = [0,1]; // set for stereo output. if you want mono output, format without [ ] brackets ex. audioOutput = 0;
var sequentialOutputs = 0; //set this to one if you want your four tracks to output on a sequential channel (i.e. set your audioOuput to 0, and sequentialOutputs to 1, and your track 0 will output on audio output 0, track 1 on audio output 1 etc.)

var maxEnvelopeVolume = 1; // set this value between 0 and 1 to allow more headroom for high resonance sweeps and lots of samples. you can compensate for a lower volume by turning up the output on your audio interface

var volumeDefault = 0.5; // this controls the default volumes of all the tracks (0 is silent and 1 is all the way up)

var volumeMixerHoldTime = nil; //sets how long (in seconds) you must hold down the two arc selection matrix buttons
//to be able to hold the volume mixer on. If set to 'nil' holding volume mixer on will be disabled

var variBright = 1; //if set to 0, disables varibright

//*************************************************\\

var grid = MonoM.new("/monome", 0);
var arc = Arc.new("/monome", 0);

var controlRowLedDefaultValues;

var sampleRecordCurrentPosition = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
var retriggerSampleRecordTimer = [Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1)]; //i don't think this gets used at all
var playbackPhasorNewPositionTrigger = [Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1)];

var currentPlaybackStart = [0, 0, 0, 0]; //stores in frames

var sampleStorageBuffer = [Buffer.alloc(s, s.sampleRate * maxRecordingLength, 1), Buffer.alloc(s, s.sampleRate * maxRecordingLength, 1), Buffer.alloc(s, s.sampleRate * maxRecordingLength, 1), Buffer.alloc(s, s.sampleRate * maxRecordingLength, 1)];

var clickStopTriggerBus = [Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1)];

var recordingSynth = [nil, nil, nil, nil];

var recordingStatusIndicator = [0, 0, 0, 0];

var playbackSynth = [Synth.basicNew("CVout", s, s.nextNodeID);, nil, nil, nil];
var playbackStatusIndicator = [0, 0, 0, 0];

var samplePlaybackDirection = [1, 1, 1, 1];
var storedPlaybackRate = [1, 1, 1, 1];

var arcSelectionLeft = [0, 0]; //left is holding status (one is held 0 is not) right is selection index
var arcSelectionRight = [0, 1];

var gridLeds = Array.fill(128, 0);
var arcLeds = [Array.fill(64, 0), Array.fill(64, 0), Array.fill(64, 0), Array.fill(64, 0)];

var playRowLedBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
var currentPlayLed = [-1, -1, -1, -1];

var triggerRecordingStatusIndicator = [0, 0, 0, 0];

var recordTriggerTimeSynth = [nil, nil, nil, nil];

var recordTriggerTimeBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];

var triggerRecordingList = [List.new(0), List.new(0), List.new(0), List.new(0)];

var triggerPlaybackPositionCount = [0, 0, 0, 0];
var triggerPlaybackStatusIndicator = [0, 0, 0, 0];
var triggerPlaybackPreSet = [0, 0, 0, 0];

var triggerRecordingSetToClear = [0, 0, 0, 0];

var triggerPlaybackFunction = [nil, nil, nil, nil];
var triggerPlaybackTempoClocks = [TempoClock.new(), TempoClock.new(), TempoClock.new(), TempoClock.new()];

var triggerTimeResetImpulseBusses = [Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1)];

var volumeMixerHeldStatus = 0;

var bitmasks = Dictionary.new; //to convert gridLeds array to bitmasks for ledmap for non-varibright

//monitor for play row leds
var playRowLedMonitor = Task({
	var interval = 0.01; //update rate for play row leds
	var playRows = [1, 3, 5, 7];
	loop {
		for(0, 3, {arg i;
			playRowLedBus[i].get({ arg value;
				if((value.asInteger != currentPlayLed[i]) && (value.asInteger >= 0), {
					currentPlayLed[i] = value.asInteger;
					for(0, 15, {arg x;
						gridLeds[x + (playRows[i] * 16)] = 1;
					});
					gridLeds[value.asInteger + (playRows[i] * 16)] = 15;
				});
			});
		});
		updateGridLeds.value;
		interval.yield;
	}
});

var updateGridLeds;
var updateArcLeds;

/*recordable buttons has to be global this has to be global because the trigger record playback function works by simulating real presses from the grid, and the trigger playback function is outside the grid OSC function*/
var recordableButtons;

var pairs;
var volumes;

var cmdPeriodFunction;

var initialize = {
	//monome usePort
	grid.usePort(gridDevicePort);
	//arc port is only assigned if an arc port is supplied.
	if(arcDevicePort.notNil, {
		arc.usePort(arcDevicePort);
	});
	//creates synth defs
	s.makeBundle(nil, {
		SynthDef.new("Recording/Playback_Reset_Trigger", { arg destination;
			FreeSelf.kr(Impulse.kr(0));
			OffsetOut.ar(destination, Impulse.ar(0));
		}).add;
		SynthDef.new("Click_Stop_Trigger", { arg destination;
			FreeSelf.kr(Impulse.kr(0));
			OffsetOut.ar(destination, Impulse.ar(0));
		}).add;
		SynthDef.new("Sample_Recording_Synth", { arg rate = 1, sampleBuffer, positionBusOutput, audioInput;
			var phasor = Phasor.ar(0, rate, 0, BufFrames.kr(sampleBuffer), 0);
			var recording = BufWr.ar(RHPF.ar(SoundIn.ar(audioInput), inputHPFfrequency), sampleBuffer, phasor, 1);
			Out.kr(positionBusOutput, phasor);
		}).add;
		if(sequentialOutputs == 0, {
			SynthDef.new("Sample_Playback_Synth", { arg rate, sampleBuffer, startValue, lengthValue, restartPhasor = 0, cutoff = 20000, resonance = 1, fmSpeed = 0, fmDepth = 0, loopStart = 0, loopLength = 1, ledPhasorOutput, position = 0, direction = 1, volume, clickStopTrigger, maxEnvelopeVolume;
				var startLoopPosition = startValue + (lengthValue * loopStart);
				var end = startValue + lengthValue;
				var endLoopPosition = (startLoopPosition + ((end - startLoopPosition) * loopLength));
				var fm = SinOsc.ar(fmSpeed, 0, fmDepth, 1);
				var duckUnit = 0.001; //is this crude?
				var playRowPosition = (startLoopPosition + (((end -startLoopPosition) * loopLength) * position));
				var phasor = Phasor.ar(TDelay.ar(In.ar(restartPhasor), duckUnit * 2), (rate * fm) * direction, startLoopPosition, endLoopPosition , playRowPosition);
				var wrap = Wrap.ar(phasor, 0, BufFrames.kr(sampleBuffer));
				var bufrd = BufRd.ar(1, sampleBuffer, wrap, 1, 2);
				var filter = RLPF.ar(bufrd, cutoff, resonance);
				var ampShape = Env.new([maxEnvelopeVolume, 0, 0, maxEnvelopeVolume], [duckUnit, duckUnit * 2, duckUnit]);
				var envelope = EnvGen.ar(ampShape, gate: In.ar(clickStopTrigger));
				Out.ar(audioOutput, (filter * volume) * envelope);
				//led position output
				Out.kr(ledPhasorOutput, LinLin.kr(phasor, startLoopPosition, endLoopPosition, 0, 16));
			}).add;
		}, { //if sequentialOutputs is not 0
			SynthDef.new("Sample_Playback_Synth", { arg rate, sampleBuffer, startValue, lengthValue, restartPhasor = 0, cutoff = 20000, resonance = 1, fmSpeed = 0, fmDepth = 0, loopStart = 0, loopLength = 1, ledPhasorOutput, position = 0, direction = 1, volume, clickStopTrigger, maxEnvelopeVolume, outputChannel;
				var startLoopPosition = startValue + (lengthValue * loopStart);
				var end = startValue + lengthValue;
				var endLoopPosition = (startLoopPosition + ((end - startLoopPosition) * loopLength));
				var fm = SinOsc.ar(fmSpeed, 0, fmDepth, 1);
				var duckUnit = 0.001; //is this crude?
				var playRowPosition = (startLoopPosition + (((end -startLoopPosition) * loopLength) * position));
				var phasor = Phasor.ar(TDelay.ar(In.ar(restartPhasor), duckUnit * 2), (rate * fm) * direction, startLoopPosition, endLoopPosition , playRowPosition);
				var wrap = Wrap.ar(phasor, 0, BufFrames.kr(sampleBuffer));
				var bufrd = BufRd.ar(1, sampleBuffer, wrap, 1, 2);
				var filter = RLPF.ar(bufrd, cutoff, resonance);
				var ampShape = Env.new([maxEnvelopeVolume, 0, 0, maxEnvelopeVolume], [duckUnit, duckUnit * 2, duckUnit]);
				var envelope = EnvGen.ar(ampShape, gate: In.ar(clickStopTrigger));
				Out.ar(outputChannel, (filter * volume) * envelope);
				//led position output
				Out.kr(ledPhasorOutput, LinLin.kr(phasor, startLoopPosition, endLoopPosition, 0, 16));
			}).add;
		});
		SynthDef("Trigger_Time_Distance_Synth", {arg outputBus, triggerInputBus;
			Out.kr(outputBus, Sweep.kr(In.ar(triggerInputBus), 1));
		}).add;
		SynthDef("Trigger_Time_Reset_Impulses", {arg outputBus;
			FreeSelf.kr(Impulse.kr(0));
			OffsetOut.ar(outputBus, Impulse.ar(0));
		}).add;
		s.sync;
		//create playback synths
		if(sequentialOutputs == 0, {
			for(0, 3, {arg i;
				playbackSynth[i] = Synth("Sample_Playback_Synth", [\rate, 0, \sampleBuffer, sampleStorageBuffer[i], \startValue, currentPlaybackStart[i], \restartPhasor, playbackPhasorNewPositionTrigger[i], \ledPhasorOutput, playRowLedBus[i], \clickStopTrigger, clickStopTriggerBus[i], \volume, volumeDefault, \maxEnvelopeVolume, maxEnvelopeVolume]);
			});
		}, { //if sequential outputs is not 0
			for(0, 3, {arg i;
				playbackSynth[i] = Synth("Sample_Playback_Synth", [\rate, 0, \sampleBuffer, sampleStorageBuffer[i], \startValue, currentPlaybackStart[i], \restartPhasor, playbackPhasorNewPositionTrigger[i], \ledPhasorOutput, playRowLedBus[i], \clickStopTrigger, clickStopTriggerBus[i], \volume, volumeDefault, \maxEnvelopeVolume, maxEnvelopeVolume, \outputChannel, audioOutput + i]);
			});
		});
		//create trigger timer synth
		for(0, 3, {arg sampleNumber;
			recordTriggerTimeSynth[sampleNumber] = Synth("Trigger_Time_Distance_Synth", [\outputBus, recordTriggerTimeBus[sampleNumber], \triggerInputBus, triggerTimeResetImpulseBusses[sampleNumber]]);
		});
		postln("Creating Sample Playback Synths 0 - 3");
		s.sync;
		//assigns arc parameters AFTER playback synths have been created, otherwise the arc won't change the parameters
		pairs = [ //changes accessable by the arc
			[ArcParameter.new("Sample Zero Cutoff", 20, 20000, 1, 2, 20000, playbackSynth[0], \cutoff, 0), ArcParameter.new("Sample Zero Resonance", 0.01, 1, 500, 1, 1, playbackSynth[0], \resonance, 0)], [ArcParameter.new("Sample Zero FM Speed", 0, 500, 5, 2, 0, playbackSynth[0], \fmSpeed, 0), ArcParameter.new("Sample Zero FM Depth", 0, 20, 25, 2, 0, playbackSynth[0], \fmDepth, 0)], [ArcParameter.new("Sample Zero Loop Start", 0, 1, 100, 2, 0, playbackSynth[0], \loopStart, 0), ArcParameter.new("Sample Zero Loop End", 0.001, 1, 100, 2, 1, playbackSynth[0], \loopLength, 0)],
			[ArcParameter.new("Sample One Cutoff", 20, 20000, 1, 2, 20000, playbackSynth[1], \cutoff, 0), ArcParameter.new("Sample One Resonance", 0.01, 1, 500, 1, 1, playbackSynth[1], \resonance, 0)], [ArcParameter.new("Sample One FM Speed", 0, 500, 5, 2, 0, playbackSynth[1], \fmSpeed, 0), ArcParameter.new("Sample One FM Depth", 0, 20, 25, 2, 0, playbackSynth[1], \fmDepth, 0)], [ArcParameter.new("Sample One Loop Start", 0, 1, 100, 2, 0, playbackSynth[1], \loopStart, 0), ArcParameter.new("Sample One Loop End", 0.001, 1, 100, 2, 1, playbackSynth[1], \loopLength, 0)],
			[ArcParameter.new("Sample Two Cutoff", 20, 20000, 1, 2, 20000, playbackSynth[2], \cutoff, 0), ArcParameter.new("Sample Two Resonance", 0.01, 1, 500, 1, 1, playbackSynth[2], \resonance, 0)], [ArcParameter.new("Sample Two FM Speed", 0, 500, 5, 2, 0, playbackSynth[2], \fmSpeed, 0), ArcParameter.new("Sample Two FM Depth", 0, 20, 25, 2, 0, playbackSynth[2], \fmDepth, 0)], [ArcParameter.new("Sample Two Loop Start", 0, 1, 100, 2, 0, playbackSynth[2], \loopStart, 0), ArcParameter.new("Sample Two Loop End", 0.001, 1, 100, 2, 1, playbackSynth[2], \loopLength, 0)],
			[ArcParameter.new("Sample Three Cutoff", 20, 20000, 1, 2, 20000, playbackSynth[3], \cutoff, 0), ArcParameter.new("Sample Three Resonance", 0.01, 1, 500, 1, 1, playbackSynth[3], \resonance, 0)], [ArcParameter.new("Sample Three FM Speed", 0, 500, 5, 2, 0, playbackSynth[3], \fmSpeed, 0), ArcParameter.new("Sample Three FM Depth", 0, 20, 25, 2, 0, playbackSynth[3], \fmDepth, 0)], [ArcParameter.new("Sample Three Loop Start", 0, 1, 100, 2, 0, playbackSynth[3], \loopStart, 0), ArcParameter.new("Sample Three Loop End", 0.001, 1, 100, 2, 1, playbackSynth[3], \loopLength, 0)],
		];
		//master volume parameters (for hidden volume mixer)
		volumes = [ArcParameter.new("Sample Zero Volume", 0, 1, 100, 2, volumeDefault, playbackSynth[0], \volume, 0), ArcParameter.new("Sample One Volume", 0, 1, 100, 2, volumeDefault, playbackSynth[1], \volume, 0), ArcParameter.new("Sample Two Volume", 0, 1, 100, 2, volumeDefault, playbackSynth[2], \volume, 0), ArcParameter.new("Sample Three Volume", 0, 1, 100, 2, volumeDefault, playbackSynth[3], \volume, 0)];
	});
	//create bitmask dictionary (use by non-varibright grids)
	for(0, 255, {arg i ;
		bitmasks.put(i.asBinaryDigits, i);
	});
	//trigger playback functions
	for(0, 3, {arg i;
		triggerPlaybackFunction[i] = {
			var count = triggerPlaybackPositionCount[i];
			triggerPlaybackTempoClocks[i].sched(0, {
				recordableButtons.value(triggerRecordingList[i][count][0], triggerRecordingList[i][count][1], triggerRecordingList[i][count][2], triggerRecordingList[i][count][3]);
				count = ((count + 1) % triggerRecordingList[i].size);
				triggerRecordingList[i][count][4];
			});
		};
	});
	//different updateGridLeds functions depending on whether varibright option is enabled
	switch(variBright, 1, {
		controlRowLedDefaultValues = [7, 3, 7, 3, 7, 3, 7, 3, 0, 3, 0, 0, 0, 3, 0, 3];
		updateGridLeds = {
			var x, y, tempGridLedsLeft, tempGridLedsRight, gridWidth;
			gridWidth = 16;
			tempGridLedsLeft = Array.fill(64, 0);
			tempGridLedsRight = Array.fill(64, 0);
			for(0, 7, { arg y;
				for(0, 15, { arg x;
					var index16 = x + (y * gridWidth);
					var index8 = x + (y * 8);
					if(x < 8, {
						tempGridLedsLeft[index8] = gridLeds[index16];
					}, {
						tempGridLedsRight[index8 - 8] = gridLeds[index16];
					});
				});
			});
			grid.levmap(0, 0, tempGridLedsLeft);
			grid.levmap(8, 0, tempGridLedsRight);
		};
		//initialize control row leds on grid
		forBy(0, 6, 2, {arg y;
			for(0, 15, {arg x;
				gridLeds[x + (y * 16)] = controlRowLedDefaultValues[x];
			});
			//initialize rate led to speed 1 (column 4)
			gridLeds[4 + (y * 16)] = 15;
		});
		//initialize faint play row leds
		forBy(1, 7, 2, {arg rows;
			for(0, 15, {arg columns;
				gridLeds[columns + (rows * 16)] = 1;
			});
		});
		//initializes arc selection matrix leds only if arcDevicePort is not nil
		if(arcDevicePort.notNil, {
			gridLeds[10 + (0 * 16)] = 15;
			gridLeds[11 + (0 * 16)] = 7;
		});
	}, 0, { //varibright disabled
		controlRowLedDefaultValues = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		updateGridLeds = {
			var gridWidth;
			var tempArrayLeft = Array.fill(8, Array.fill(8, 0));
			var tempArrayRight = Array.fill(8, Array.fill(8, 0));
			var finalArrayLeft = Array.fill(8, 0);
			var finalArrayRight = Array.fill(8, 0);
			gridWidth = 16;
			for(0, 7, {arg rows;
				for(15, 0, {arg columns;
					var roundedBrightness;
					if(gridLeds[columns + (rows * 16)] > 6, {
						roundedBrightness = 1;
					}, {
						roundedBrightness = 0;
					});
					if(columns > 7, {
						tempArrayRight[rows][((columns - 8) * -1) + 7] = roundedBrightness;
					}, {
						tempArrayLeft[rows][(columns * -1) + 7] = roundedBrightness;
					});

				});
				finalArrayLeft[rows] = bitmasks.at(tempArrayLeft[rows]);
				finalArrayRight[rows] = bitmasks.at(tempArrayRight[rows]);
			});
			grid.ledmap(0, 0, finalArrayLeft);
			grid.ledmap(8, 0, finalArrayRight);
		};
		//initialize control row leds on grid
		forBy(0, 6, 2, {arg y;
			for(0, 15, {arg x;
				gridLeds[x + (y * 16)] = controlRowLedDefaultValues[x];
			});
			//initialize rate led to speed 1 (column 4)
			gridLeds[4 + (y * 16)] = 7;
		});
		//initializes arc selection matrix leds only if arcDevicePort is not nil
		if(arcDevicePort.notNil, {
			gridLeds[10 + (0 * 16)] = 7;
			gridLeds[11 + (0 * 16)] = 7;
		});
	});
	updateArcLeds = {arg encoderNumber, name;
		var encArray = { arg encoderNumber, ledValue, fineLedLevel;
			var ledLevel = 15;
			var encoderTemporaryArray = Array.newClear(64);
			if(arcSelectionRight[0] == 1, {
				ledLevel = 5;
			});
			for(0, (ledValue - 1).thresh(0), {arg i;
				encoderTemporaryArray[i] = ledLevel;
			});
			encoderTemporaryArray[ledValue] = fineLedLevel;
			for(ledValue + 1, 63, {arg i;
				encoderTemporaryArray[i] = 0;
			});
			encoderTemporaryArray;
		};
		var encArrayTemp;
		if(arcSelectionRight[0] == 1, {
			encArrayTemp = encArray.value(encoderNumber, name.arcLedValue, name.arcLedValueFine(5));
		}, {
			encArrayTemp = encArray.value(encoderNumber, name.arcLedValue, name.arcLedValueFine);
		});
		arc.ringmap(encoderNumber, encArrayTemp);
	};
	//initializes grid leds
	updateGridLeds.value;
	//initializes arc leds
	if(arcDevicePort.notNil, {
		updateArcLeds.value(0, pairs[0][0]);
		updateArcLeds.value(1, pairs[0][1]);
		updateArcLeds.value(2, pairs[1][0]);
		updateArcLeds.value(3, pairs[1][1]);
	});
};
//OSC function for grid 128
OSCdef(\grid128,
	{ arg message, time, addr, recvPort;
		//message 1 = x axis (columns 0-15) message 2 = y axis (rows 0-7)
		var recordingFunction = {arg sampleNumber, messageOne, messageTwo, playRowBoolean;
			if(triggerRecordingSetToClear[sampleNumber] == 1, {
				triggerRecordingList[sampleNumber].clear;
				triggerRecordingSetToClear[sampleNumber] = 0;
			});
			recordTriggerTimeBus[sampleNumber].get({arg index;
				triggerRecordingList[sampleNumber].add([sampleNumber, messageOne, messageTwo, playRowBoolean, index]);
				Synth("Trigger_Time_Reset_Impulses", [\outputBus, triggerTimeResetImpulseBusses[sampleNumber]]);
			});
		};
		var evenRow = {arg sampleNumber, messageOne, messageTwo, messageThree;
			if(messageOne > 9, {
				nonRecordableButtons.value(sampleNumber, messageOne, messageTwo, messageThree);
			}, {
				if(messageThree == 1, {
					if(triggerRecordingStatusIndicator[sampleNumber] == 1, {
						recordingFunction.value(sampleNumber, messageOne, messageTwo, 0);
					});
					recordableButtons.value(sampleNumber, messageOne, messageTwo, 0);
				});
			});
		};
		var oddRow = {arg sampleNumber, messageOne, messageTwo, messageThree;
			if(messageThree == 1, {
				if(triggerRecordingStatusIndicator[sampleNumber] == 1, {
					recordingFunction.value(sampleNumber, messageOne, messageTwo, 1);
				});
				recordableButtons.value(sampleNumber, messageOne, messageTwo, 1);
			});
		};
		//non recordable buttons function gets added to conditionally later
		var nonRecordableButtons = nil;
		//recordable buttons was declared in an outer scope so it can be used by the trigger playback function
		recordableButtons = {arg sampleNumber, messageOne, messageTwo, playRowBoolean;
			var rates = [0.25, 0.375, 0.5, 0.75, 1, 1.5, 2, 3];
			var ledOffsets = [0, 2, 4, 6];
			//messages get parsed depending on whether they are in the play row or the control row
			switch(playRowBoolean, 1, { //play row
				var positions = [0, 0.0625, 0.125, 0.1875, 0.25, 0.3125, 0.375, 0.4375, 0.5, 0.5625, 0.625, 0.6875, 0.75, 0.8125, 0.875, 0.9375];
				playbackSynth[sampleNumber].set(\position, positions[messageOne]);
				Synth("Recording/Playback_Reset_Trigger", [\destination,  playbackPhasorNewPositionTrigger[sampleNumber]]);
				Synth("Click_Stop_Trigger", [\destination,  clickStopTriggerBus[sampleNumber]]);
				postln("Sample" + sampleNumber + "Position =" + positions[messageOne]);
			}, 0, { //control row, recordable section
				if(messageOne == 9, { //playback on/off
					if(playbackStatusIndicator[sampleNumber] == 1, {
						playbackSynth[sampleNumber].set(\rate, 0);
						playbackStatusIndicator[sampleNumber] = 0;
						gridLeds[9 + (ledOffsets[sampleNumber] * 16)] = 3;
						updateGridLeds.value;
						postln("Stoping Playback of Sample" + sampleNumber);
					}, {
						playbackSynth[sampleNumber].set(\rate, storedPlaybackRate[sampleNumber]);
						playbackStatusIndicator[sampleNumber] = 1;
						gridLeds[9 + (ledOffsets[sampleNumber] * 16)] = 15;
						updateGridLeds.value;
						postln("Playing Sample" + sampleNumber);
					});
				});
				if(((messageOne >= 0) && (messageOne <= 7)), { //pitch selection
					if(playbackStatusIndicator[sampleNumber] == 1, {
						playbackSynth[sampleNumber].set(\rate, rates[messageOne]);
						storedPlaybackRate[sampleNumber] = rates[messageOne];
					}, {
						storedPlaybackRate[sampleNumber] = rates[messageOne];
					});
					for(0, 7, {arg i;
						gridLeds[i + (ledOffsets[sampleNumber] * 16)] = controlRowLedDefaultValues[i];
					});
					gridLeds[messageOne + (ledOffsets[sampleNumber] * 16)] = 15;
					updateGridLeds.value;
					postln("Sample" + sampleNumber + "Rate =" + rates[messageOne]);
				});
				if(messageOne == 8, { //sample direction
					samplePlaybackDirection[sampleNumber] = samplePlaybackDirection[sampleNumber] * -1;
					playbackSynth[sampleNumber].set(\direction, samplePlaybackDirection[sampleNumber]);
					switch(samplePlaybackDirection[sampleNumber], 1, {
						gridLeds[8 + (ledOffsets[sampleNumber] * 16)] = 0;
						updateGridLeds.value;
					}, -1, {
						gridLeds[8 + (ledOffsets[sampleNumber] * 16)] = 15;
						updateGridLeds.value;
					});
					postln("Direction on Track" + sampleNumber + "=" + samplePlaybackDirection[sampleNumber]);
				});
			});
		};
		//non recordable buttons functionality except for the arc matrix selection, this gets added on conditionally later
		nonRecordableButtons = nonRecordableButtons.addFunc {arg sampleNumber, messageOne, messageTwo, messageThree;
			//the arc control selection matrix is the reason I have not gotten rid of the messageThree arguments, if I got rid of message three I could use a switch instead of if conditionals
			var ledOffsets = [0, 2, 4, 6];
			if(messageOne == 15 && messageThree == 1, { //sample record button
				switch(recordingStatusIndicator[sampleNumber], 0, {
					if(recordingSynth[sampleNumber] == nil, { //if this is the very first recording
						recordingSynth[sampleNumber] = Synth.new("Sample_Recording_Synth", [\rate, 1, \sampleBuffer, sampleStorageBuffer[sampleNumber], \positionBusOutput, sampleRecordCurrentPosition[sampleNumber], \audioInput, audioInput]);
					}, {
						s.makeBundle(nil, {
							//retrieves the current position of the recording synth to determine the start point
							//for the new recording.
							sampleRecordCurrentPosition[sampleNumber].get({arg i;
								currentPlaybackStart[sampleNumber] = i;
							});
							s.sync;
							recordingSynth[sampleNumber].set(\rate, 1);
						});
					});
					recordingStatusIndicator[sampleNumber] = 1;
					gridLeds[15 + (ledOffsets[sampleNumber] * 16)] = 15;
					updateGridLeds.value;
					postln("Recording Sample" + sampleNumber);
				}, 1, {
					s.makeBundle(nil, {
						//stops recording by turning phasors rate to 0
						recordingSynth[sampleNumber].set(\rate, 0);
						s.sync;
						sampleRecordCurrentPosition[sampleNumber].get({arg i;
							if(currentPlaybackStart[sampleNumber] >= i, {
								//if wrapping around end of recording buffer
								playbackSynth[sampleNumber].set(\startValue, currentPlaybackStart[sampleNumber],
									\lengthValue, (s.sampleRate * maxRecordingLength) + (i - currentPlaybackStart[sampleNumber])
								);
								postln("Sucessfully recorded wrapping around the end of recording buffer on track" + sampleNumber);
							}, {
								//normal recording
								playbackSynth[sampleNumber].set(\startValue, currentPlaybackStart[sampleNumber], \lengthValue, i - currentPlaybackStart[sampleNumber]);
							}
							);
						});
						s.sync;
						recordingStatusIndicator[sampleNumber] = 0;
						Synth("Recording/Playback_Reset_Trigger", [\destination,  playbackPhasorNewPositionTrigger[sampleNumber]]);
						s.sync;
						Synth("Click_Stop_Trigger", [\destination,  clickStopTriggerBus[sampleNumber]]);
						s.sync;
					}); //end of make bundle
					gridLeds[15 + (ledOffsets[sampleNumber] * 16)] = 3;
					updateGridLeds.value;
					postln("Stopping Recording of Sample" + sampleNumber);
				});
			});
			if(messageOne == 13 && messageThree == 1, { //activate trigger record
				switch(triggerRecordingStatusIndicator[sampleNumber], 1, {
					if(triggerRecordingSetToClear[sampleNumber] == 1, {
						triggerRecordingSetToClear[sampleNumber] = 0;
						triggerRecordingStatusIndicator[sampleNumber] = 0;
						gridLeds[13 + (ledOffsets[sampleNumber] * 16)] = 3;
						updateGridLeds.value;
						post("Trigger Recorder" + sampleNumber + "released from PreSet State");
					}, {
						recordTriggerTimeBus[sampleNumber].get({arg index;
							triggerRecordingList[sampleNumber][0].put(4, index);
							Synth("Trigger_Time_Reset_Impulses", [\outputBus, triggerTimeResetImpulseBusses[sampleNumber]]);
						});
						triggerRecordingStatusIndicator[sampleNumber] = 0;
						gridLeds[13 + (ledOffsets[sampleNumber] * 16)] = 3;
						updateGridLeds.value;
						postln("Stopping Recording of Sample" + sampleNumber + "triggers");
						if(triggerPlaybackPreSet[sampleNumber] == 1, { //if playback PreSet is on
							triggerPlaybackFunction[sampleNumber].value;
							triggerPlaybackStatusIndicator[sampleNumber] = 1;
							triggerPlaybackPreSet[sampleNumber] = 0;
							postln("Playing Trigger Recording from PreSet State on Track" + sampleNumber);
						});
					});
				}, 0, {
					Synth("Trigger_Time_Reset_Impulses", [\outputBus, triggerTimeResetImpulseBusses[sampleNumber]]);
					triggerRecordingStatusIndicator[sampleNumber] = 1;
					triggerRecordingSetToClear[sampleNumber] = 1;
					gridLeds[13 + (ledOffsets[sampleNumber] * 16)] = 15;
					updateGridLeds.value;
					postln("Starting Recording of Sample" + sampleNumber + "triggers");
				});
			});
			if(messageOne == 14 && messageThree == 1, { //play triggers
				switch(triggerPlaybackStatusIndicator[sampleNumber], 0, {
					switch(triggerRecordingStatusIndicator[sampleNumber], 1, {
						triggerPlaybackPreSet[sampleNumber] = 1;
						gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 15;
						updateGridLeds.value;
						postln("Trigger Playback Pre Set on Track" + sampleNumber);
					}, 0, {
						triggerPlaybackFunction[sampleNumber].value;
						triggerPlaybackStatusIndicator[sampleNumber] = 1;
						gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 15;
						updateGridLeds.value;
						triggerPlaybackPreSet[sampleNumber] = 0;
						postln("Playing Trigger Recording on Track" + sampleNumber);
					});
				}, 1, {
					triggerPlaybackTempoClocks[sampleNumber].clear;
					triggerPlaybackPositionCount[sampleNumber] = 0;
					triggerPlaybackStatusIndicator[sampleNumber] = 0;
					gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 0;
					updateGridLeds.value;
					postln("Stopping Position Playback on Track " + sampleNumber);
				});
			});
		}; //end non recording
		if(arcDevicePort.notNil, {
			nonRecordableButtons = nonRecordableButtons.addFunc{arg sampleNumber, messageOne, messageTwo, messageThree;
				var matrixIndexes = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]];
				if((messageOne == 12) || (messageOne == 11) || (messageOne == 10), { //arc control selection matrix
					var messageOneOffset = messageOne - 10;
					var matrixLedLocations = [[10, 0], [11, 0], [12, 0], [10, 2], [11, 2], [12, 2], [10, 4], [11, 4], [12, 4], [10, 6], [11, 6], [12, 6]];
					if (messageThree == 1, {
						switch(arcSelectionLeft[0], 0,{
							if(matrixIndexes[sampleNumber][messageOneOffset] == arcSelectionRight[1], { //if you try to select slot one where slot two already is
								arcSelectionRight[1] = matrixIndexes[sampleNumber][(messageOneOffset + 1) % 3];
							});
							arcSelectionLeft[0] = 1; //one means true or is held
							if(volumeMixerHeldStatus == 0, {
								arcSelectionLeft[1] = matrixIndexes[sampleNumber][messageOneOffset];
								updateArcLeds.value(0, pairs[arcSelectionLeft[1]][0]);
								updateArcLeds.value(1, pairs[arcSelectionLeft[1]][1]);
								postln("Selection Left Index =" + arcSelectionLeft[1]);
							});
						}, 1, {
							arcSelectionRight[0] = 1;
							arcSelectionRight[1] = matrixIndexes[sampleNumber][messageOneOffset];
							//this is the hidden volume mixer area
							for(0, 3, {arg i;
								//updateArcLeds.value(i, volumes[i].arcLedValue, 5);
								updateArcLeds.value(i, volumes[i]);
							});
							postln("Selection Right Index =" + arcSelectionRight[1]);
							postln("Displaying Master Volume Mixer");
							if(volumeMixerHoldTime.notNil, {
								switch(volumeMixerHeldStatus, 0, { //holding volume mixer on
									AppClock.clear;
									AppClock.sched(volumeMixerHoldTime , {
										if(arcSelectionRight[0] == 1, { //if right selection is still held down
											volumeMixerHeldStatus = 1;
											("Holding Volume Mixer On").postln;
										})
									});
								}, 1, {
									volumeMixerHeldStatus = 0;
									("Volume Mixer is not being held").postln;
								});
							});
						});
						for(10, 12, {arg x; //clear and reset arc selection matrix leds
							forBy(0, 6, 2, {arg y;
								gridLeds[x + (y * 16)] = 0;
							});
						});
						//masked x + (y * width)
						gridLeds[matrixLedLocations[arcSelectionLeft[1]][0] + (matrixLedLocations[arcSelectionLeft[1]][1] * 16)] = 15;
						gridLeds[matrixLedLocations[arcSelectionRight[1]][0] + (matrixLedLocations[arcSelectionRight[1]][1] * 16)] = 7;
						updateGridLeds.value;
					});
					if(messageThree == 0, {
						if(arcSelectionLeft[0] == 1 && arcSelectionLeft[1] == matrixIndexes[sampleNumber][messageOneOffset], {
							arcSelectionLeft[0] = 0;
							//postln("Releasing Selection Left with Index" + arcSelectionLeft[1]);
						});
						if(arcSelectionRight[0] == 1 && arcSelectionRight[1] == matrixIndexes[sampleNumber][messageOneOffset], {
							if(volumeMixerHeldStatus == 0, {
								arcSelectionRight[0] = 0;
								updateArcLeds.value(0, pairs[arcSelectionLeft[1]][0]); //display arc selection parameters instead of volumes
								updateArcLeds.value(1, pairs[arcSelectionLeft[1]][1]);
								updateArcLeds.value(2, pairs[arcSelectionRight[1]][0]);
								updateArcLeds.value(3, pairs[arcSelectionRight[1]][1]);
								postln("Hiding Master Volume Mixer");
								//postln("Releasing Selection Right with Index" + arcSelectionRight[1]);
							})
						});
					});
				});
			};
		});
		//messages from the grid gets parsed by row
		switch(message[2], 0, {
			evenRow.value(0, message[1], message[2], message[3]);
		}, 1, {
			oddRow.value(0, message[1], message[2], message[3]);
		}, 2, {
			evenRow.value(1, message[1], message[2], message[3]);
		}, 3, {
			oddRow.value(1, message[1], message[2], message[3]);
		}, 4, {
			evenRow.value(2, message[1], message[2], message[3]);
		}, 5, {
			oddRow.value(2, message[1], message[2], message[3]);
		}, 6, {
			evenRow.value(3, message[1], message[2], message[3]);
		}, 7, {
			oddRow.value(3, message[1], message[2], message[3]);
		});
}, "/monome/grid/key", NetAddr("127.0.0.1", gridDevicePort));
//OSC function for arc 4
OSCdef(\arc4,
	{ arg message, time, addr, recvPort;
		var arcFunctions = {arg name, messageOne, messageTwo;
			name.change(messageTwo);
			updateArcLeds.value(messageOne, name);
		};
		switch(arcSelectionRight[0], 1, { //hidden volume mixer
			switch(message[1], 0, {
				arcFunctions.value(volumes[0], 0, message[2]);
			}, 1, {
				arcFunctions.value(volumes[1], 1, message[2]);
			}, 2, {
				arcFunctions.value(volumes[2], 2, message[2]);
			}, 3, {
				arcFunctions.value(volumes[3], 3, message[2]);
			});
		}, 0, {
			switch(message[1], 0, {
				arcFunctions.value(pairs[arcSelectionLeft[1]][0], 0, message[2]);
			}, 1, {
				arcFunctions.value(pairs[arcSelectionLeft[1]][1], 1, message[2]);
			}, 2, {
				arcFunctions.value(pairs[arcSelectionRight[1]][0], 2, message[2]);
			}, 3, {
				arcFunctions.value(pairs[arcSelectionRight[1]][1], 3, message[2]);
			});
		});
}, "/monome/enc/delta", NetAddr("127.0.0.1", arcDevicePort));
playRowLedMonitor.play;
OSCdef(\grid128).enable;
OSCdef(\arc4).enable;
initialize.value();
CmdPeriod.removeAll;
cmdPeriodFunction = {
	playRowLedMonitor.stop;
	for(0,3, {arg i;
		sampleRecordCurrentPosition[i].free;
		retriggerSampleRecordTimer[i].free;
		playbackPhasorNewPositionTrigger[i].free;
		clickStopTriggerBus[i].free;
		playRowLedBus[i].free;
		recordTriggerTimeBus[i].free;
		triggerTimeResetImpulseBusses[i].free;
		//tempo clock for trigger playback
		triggerPlaybackTempoClocks[i].clear;
	});
	postln("Busses freed");
	Buffer.freeAll;
	postln("Buffers freed");
};
CmdPeriod.add(cmdPeriodFunction);
"Animalation is ready";
)