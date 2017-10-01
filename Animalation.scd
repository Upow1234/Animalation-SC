(

//*************************************************\\

// ESSENTIAL TO MAKE YOUR GRID AND ARC WORK WITH THIS PROGRAM:
// enter the numbers you see in the post window after "Device connected on port: " for both your grid 128 and your arc

~gridDevicePort = 16139;
~arcDevicePort = 16159; //set this option to 'nil' to be able to use Animalation without an arc 4

//  USER OPTIONS AREA  \\

// audio inputs and outputs start counting from 0 (input 1 on your interface is 0, input 2 is 1 etc.)

~audioInput = 0;
~maxRecordingLength = 120; // the maximum number of seconds you can record one sample
~audioOutput = [0, 1]; // set for stereo output. if you want mono output, format without [ ] brackets ex. ~audioOutput = 0;

~maxEnvelopeVolume = 1; // set this value between 0 and 1 to allow more headroom for high resonance sweeps and lots of samples. you can compensate for a lower volume by turning up the output on your audio interface

~volumeDefault = 0.5; // this controls the default volumes of all the tracks (0 is silent and 1 is all the way up)

~volumeMixerHoldTime = 1; //sets how long (in seconds) you must hold down the two arc selection matrix buttons
//to be able to hold the volume mixer on. If set to 'nil' holding volume mixer on will be disabled

//*************************************************\\

s.reboot; //releases all busses for reallocation

s = Server.local;

~grid128 = MonoM.new("/monome", 0);
~arc4 = Arc.new("/monome", 0);

Buffer.freeAll; //essential or buffers start piling up in RAM

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

	var recording = BufWr.ar(SoundIn.ar(audioInput), sampleBuffer, phasor, 1);

	Out.kr(positionBusOutput, phasor);

}).add;

SynthDef.new("Sample_Playback_Synth", { arg rate, sampleBuffer, startValue, lengthValue, restartPhasor = 0, cutoff = 20000, resonance = 1, fmSpeed = 0, fmDepth = 0, loopStart = 0, loopLength = 1, ledPhasorOutput, position = 0, direction = 1, volume, clickStopTrigger, maxEnvelopeVolume;

	var start = startValue;

	var startLoopPosition = start + (lengthValue * loopStart);

	var end = start + lengthValue;

	var endLoopPosition = (startLoopPosition + ((end - startLoopPosition) * loopLength));

	var fm = SinOsc.ar(fmSpeed, 0, fmDepth, 1);

	var duckUnit = 0.001;

	var playRowPosition = (startLoopPosition + (((end -startLoopPosition) * loopLength) * position));

	var phasor = Phasor.ar(TDelay.ar(In.ar(restartPhasor), duckUnit * 2), (rate * fm) * direction, startLoopPosition, endLoopPosition , playRowPosition);

	var wrap = Wrap.ar(phasor, 0, BufFrames.kr(sampleBuffer));

	var bufrd = BufRd.ar(1, sampleBuffer, wrap, 1, 2);

	var filter = RLPF.ar(bufrd, cutoff, resonance);

	var ampShape = Env.new([maxEnvelopeVolume, 0, 0, maxEnvelopeVolume], [duckUnit, duckUnit * 2, duckUnit]);

	var envelope = EnvGen.ar(ampShape, gate: In.ar(clickStopTrigger));

	Out.ar(~audioOutput, (filter * volume) * envelope);

	//led position output
	Out.kr(ledPhasorOutput, LinLin.kr(phasor, startLoopPosition, endLoopPosition, 0, 16));

}).add;

SynthDef("Trigger_Time_Distance_Synth", {arg outputBus, triggerInputBus;

	Out.kr(outputBus, Sweep.kr(In.ar(triggerInputBus), 1));

}).add;

SynthDef("Trigger_Time_Reset_Impulses", {arg outputBus;

	FreeSelf.kr(Impulse.kr(0));

	OffsetOut.ar(outputBus, Impulse.ar(0));

}).add;


s.waitForBoot({

	~grid128.usePort(~gridDevicePort);

	if(~arcDevicePort.notNil, {
		~arc4.usePort(~arcDevicePort);
	});

	~sampleRecordCurrentPosition = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
	~retriggerSampleRecordTimer = [Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1)];
	~playbackPhasorNewPositionTrigger = [Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1)];

	~currentPlaybackStart = [0, 0, 0, 0]; //stores in frames
	~currentPlaybackEnd = [48000, 48000, 48000, 48000]; //stores in frames. 1 is just filler.

	~sampleStorageBuffer = [Buffer.alloc(s, s.sampleRate * ~maxRecordingLength, 1), Buffer.alloc(s, s.sampleRate * ~maxRecordingLength, 1), Buffer.alloc(s, s.sampleRate * ~maxRecordingLength, 1), Buffer.alloc(s, s.sampleRate * ~maxRecordingLength, 1)];

	~clickStopTriggerBus = [Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1)];

	~recordingSynth = [nil, nil, nil, nil];

	~recordingStatusIndicator = [0, 0, 0, 0];

	~playbackSynth = [nil, nil, nil, nil];
	~playbackStatusIndicator = [0, 0, 0, 0];

	~samplePlaybackDirection = [1, 1, 1, 1];
	~storedPlaybackRate = [1, 1, 1, 1];

	~arcSelectionLeft = [0, 0]; //left is holding status (one is held 0 is not) right is selection index
	~arcSelectionRight = [0, 1];

	~gridLeds = Array.fill(128, 0);
	~arcLeds = [Array.fill(64, 0), Array.fill(64, 0), Array.fill(64, 0), Array.fill(64, 0)];

	~controlRowLedDefaultValues = [7, 3, 7, 3, 7, 3, 7, 3, 0, 3, 0, 0, 0, 3, 0, 3];

	~playRowLedBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];
	~currentPlayLed = [0, 0, 0, 0];

	~triggerRecordingStatusIndicator = [0, 0, 0, 0];

	~recordTriggerTimeSynth = [nil, nil, nil, nil];

	~recordTriggerTimeBus = [Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1), Bus.control(s, 1)];

	~triggerRecordingList = [List.new(0), List.new(0), List.new(0), List.new(0)];

	~triggerPlaybackPositionCount = [0, 0, 0, 0];
	~triggerPlaybackStatusIndicator = [0, 0, 0, 0];
	~triggerPlaybackPreSet = [0, 0, 0, 0];

	~triggerRecordingSetToClear = [0, 0, 0, 0];

	~triggerPlaybackFunction = [nil, nil, nil, nil];
	~triggerPlaybackTempoClocks = [TempoClock.new(), TempoClock.new(), TempoClock.new(), TempoClock.new()];

	~triggerTimeResetImpulseBusses = [Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1), Bus.audio(s, 1)];

	~volumeMixerHeldStatus = 0;

	OSCFunc.newMatching( //grid functionality
		{ arg message, time, addr, recvPort;
			//message 1 = x axis (columns 0-15) message 2 = y axis (rows 0-7)

			var recordingFunction = {arg sampleNumber, messageOne, messageTwo, playRowBoolean;

				if(~triggerRecordingSetToClear[sampleNumber] == 1, {
					~triggerRecordingList[sampleNumber].clear;
					~triggerRecordingSetToClear[sampleNumber] = 0;
				});

				~recordTriggerTimeBus[sampleNumber].get({arg index;

					~triggerRecordingList[sampleNumber].add([sampleNumber, messageOne, messageTwo, playRowBoolean, index]);
					Synth("Trigger_Time_Reset_Impulses", [\outputBus, ~triggerTimeResetImpulseBusses[sampleNumber]]);

				});

			};

			var evenRow = {arg sampleNumber, messageOne, messageTwo, messageThree;

				if(messageOne > 9, {
					~nonRecordableButtons.value(sampleNumber, messageOne, messageTwo, messageThree);
				}, {
					if(messageThree == 1, {
						if(~triggerRecordingStatusIndicator[sampleNumber] == 1, {
							recordingFunction.value(sampleNumber, messageOne, messageTwo, 0);
						});
						~recordableButtons.value(sampleNumber, messageOne, messageTwo, 0);
					});
				});

			};

			var oddRow = {arg sampleNumber, messageOne, messageTwo, messageThree;

				if(messageThree == 1, {
					if(~triggerRecordingStatusIndicator[sampleNumber] == 1, {
						recordingFunction.value(sampleNumber, messageOne, messageTwo, 1);
					});
					~recordableButtons.value(sampleNumber, messageOne, messageTwo, 1);
				});

			};

			if(addr.port == ~gridDevicePort, {
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
			});

	}, "/monome/grid/key");


	~recordableButtons = {arg sampleNumber, messageOne, messageTwo, playRowBoolean;

		var rates = [0.25, 0.375, 0.5, 0.75, 1, 1.5, 2, 3];
		var ledOffsets = [0, 2, 4, 6];

		switch(playRowBoolean, 1, { //play row

			var positions = [0, 0.0625, 0.125, 0.1875, 0.25, 0.3125, 0.375, 0.4375, 0.5, 0.5625, 0.625, 0.6875, 0.75, 0.8125, 0.875, 0.9375];

			~playbackSynth[sampleNumber].set(\position, positions[messageOne]);

			Synth("Recording/Playback_Reset_Trigger", [\destination,  ~playbackPhasorNewPositionTrigger[sampleNumber]]);
			Synth("Click_Stop_Trigger", [\destination,  ~clickStopTriggerBus[sampleNumber]]);

			postln("Sample" + sampleNumber + "Position =" + positions[messageOne]);

		}, 0, {

			if(messageOne == 9, { //playback on/off

				if(~playbackStatusIndicator[sampleNumber] == 1, {
					~playbackSynth[sampleNumber].set(\rate, 0);

					~playbackStatusIndicator[sampleNumber] = 0;

					~gridLeds[9 + (ledOffsets[sampleNumber] * 16)] = 3;
					~updateGridLeds.value;

					postln("Stoping Playback of Sample" + sampleNumber);
				}, {
					~playbackSynth[sampleNumber].set(\rate, ~storedPlaybackRate[sampleNumber]);

					~playbackStatusIndicator[sampleNumber] = 1;

					~gridLeds[9 + (ledOffsets[sampleNumber] * 16)] = 15;
					~updateGridLeds.value;

					postln("Playing Sample" + sampleNumber);
				});

			});

			if(((messageOne >= 0) && (messageOne <= 7)), { //pitch selection

				if(~playbackStatusIndicator[sampleNumber] == 1, {
					~playbackSynth[sampleNumber].set(\rate, rates[messageOne]);
					~storedPlaybackRate[sampleNumber] = rates[messageOne];
				}, {
					~storedPlaybackRate[sampleNumber] = rates[messageOne];
				}
				);

				for(0, 7, {arg i;
					~gridLeds[i + (ledOffsets[sampleNumber] * 16)] = ~controlRowLedDefaultValues[i];
				});

				~gridLeds[messageOne + (ledOffsets[sampleNumber] * 16)] = 15;
				~updateGridLeds.value;

				postln("Sample" + sampleNumber + "Rate =" + rates[messageOne]);

			});

			if(messageOne == 8, { //sample direction

				~samplePlaybackDirection[sampleNumber] = ~samplePlaybackDirection[sampleNumber] * -1;

				~playbackSynth[sampleNumber].set(\direction, ~samplePlaybackDirection[sampleNumber]);

				switch(~samplePlaybackDirection[sampleNumber], 1, {
					~gridLeds[8 + (ledOffsets[sampleNumber] * 16)] = 0;
					~updateGridLeds.value;
				}, -1, {
					~gridLeds[8 + (ledOffsets[sampleNumber] * 16)] = 15;
					~updateGridLeds.value;
				});

				postln("Direction on Track" + sampleNumber + "=" + ~samplePlaybackDirection[sampleNumber]);
			});

		});

	};


	~nonRecordableButtons = {arg sampleNumber, messageOne, messageTwo, messageThree;

		var matrixIndexes = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]];
		var ledOffsets = [0, 2, 4, 6];

		if(~arcDevicePort.notNil, {
			if((messageOne == 12) || (messageOne == 11) || (messageOne == 10), { //arc control selection matrix

				var messageOneOffset = messageOne - 10;
				var matrixLedLocations = [[10, 0], [11, 0], [12, 0], [10, 2], [11, 2], [12, 2], [10, 4], [11, 4], [12, 4], [10, 6], [11, 6], [12, 6]];

				if (messageThree == 1, {

					switch(~arcSelectionLeft[0], 0,{

						if(matrixIndexes[sampleNumber][messageOneOffset] == ~arcSelectionRight[1], { //if you try to select slot one where slot two already is
							~arcSelectionRight[1] = matrixIndexes[sampleNumber][(messageOneOffset + 1) % 3];
						});

						~arcSelectionLeft[0] = 1; //one means true or is held

						if(~volumeMixerHeldStatus == 0, {
							~arcSelectionLeft[1] = matrixIndexes[sampleNumber][messageOneOffset];

							~updateArcLeds.value(0, ~pairs[~arcSelectionLeft[1]][0].arcLedValue);
							~updateArcLeds.value(1, ~pairs[~arcSelectionLeft[1]][1].arcLedValue);

							postln("Selection Left Index =" + ~arcSelectionLeft[1]);
						});

					}, 1, {

						~arcSelectionRight[0] = 1;
						~arcSelectionRight[1] = matrixIndexes[sampleNumber][messageOneOffset];

						//this is the hidden volume mixer area

						for(0, 3, {arg i;
							~updateArcLeds.value(i, ~volumes[i].arcLedValue, 5);
						});

						postln("Selection Right Index =" + ~arcSelectionRight[1]);
						postln("Displaying Master Volume Mixer");

						if(~volumeMixerHoldTime.notNil, {
							switch(~volumeMixerHeldStatus, 0, { //holding volume mixer on

								AppClock.clear;
								AppClock.sched(~volumeMixerHoldTime , { //need to cancel this out if it gets rescheudled!!!!!
									if(~arcSelectionRight[0] == 1, { //if right selection is still held down
										~volumeMixerHeldStatus = 1;
										("Holding Volume Mixer On").postln;
									})

								});
							}, 1, {
								~volumeMixerHeldStatus = 0;
								("Volume Mixer is not being held").postln;
							});
						});

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
						//postln("Releasing Selection Left with Index" + ~arcSelectionLeft[1]);
					});


					if(~arcSelectionRight[0] == 1 && ~arcSelectionRight[1] == matrixIndexes[sampleNumber][messageOneOffset], {

						if(~volumeMixerHeldStatus == 0, {

							~arcSelectionRight[0] = 0;

							~updateArcLeds.value(0, ~pairs[~arcSelectionLeft[1]][0].arcLedValue); //display arc selection parameters instead of volumes
							~updateArcLeds.value(1, ~pairs[~arcSelectionLeft[1]][1].arcLedValue);
							~updateArcLeds.value(2, ~pairs[~arcSelectionRight[1]][0].arcLedValue);
							~updateArcLeds.value(3, ~pairs[~arcSelectionRight[1]][1].arcLedValue);

							postln("Hiding Master Volume Mixer");
							//postln("Releasing Selection Right with Index" + ~arcSelectionRight[1]);
						})
					});

				});

			});
		});

		if(messageOne == 15 && messageThree == 1, { //sample record button

			switch(~recordingStatusIndicator[sampleNumber], 0, {

				if(~recordingSynth[sampleNumber] == nil, { //if this is the very first recording

					~recordingSynth[sampleNumber] = Synth.new("Sample_Recording_Synth", [\rate, 1, \sampleBuffer, ~sampleStorageBuffer[sampleNumber], \positionBusOutput, ~sampleRecordCurrentPosition[sampleNumber], \audioInput, ~audioInput]);

				}, {

					Synth("Recording/Playback_Reset_Trigger", [\destination, ~retriggerSampleRecordTimer[sampleNumber]]);
					~recordingSynth[sampleNumber].set(\rate, 1);

					~sampleRecordCurrentPosition[sampleNumber].get({arg i;
						~currentPlaybackStart[sampleNumber] = i;
					});
				});

				~recordingStatusIndicator[sampleNumber] = 1;

				~gridLeds[15 + (ledOffsets[sampleNumber] * 16)] = 15;
				~updateGridLeds.value;

				postln("Recording Sample" + sampleNumber);

			}, 1, {

				~recordingSynth[sampleNumber].set(\rate, 0);
				~sampleRecordCurrentPosition[sampleNumber].get({arg i;
					~currentPlaybackEnd[sampleNumber] = i;

					~playbackSynth[sampleNumber].set(\lengthValue, i - ~currentPlaybackStart[sampleNumber]);

				});

				~recordingStatusIndicator[sampleNumber] = 0;

				~playbackSynth[sampleNumber].set(\startValue, ~currentPlaybackStart[sampleNumber]);

				Synth("Recording/Playback_Reset_Trigger", [\destination,  ~playbackPhasorNewPositionTrigger[sampleNumber]]);

				Synth("Click_Stop_Trigger", [\destination,  ~clickStopTriggerBus[sampleNumber]]);

				~gridLeds[15 + (ledOffsets[sampleNumber] * 16)] = 3;
				~updateGridLeds.value;

				postln("Stopping Recording of Sample" + sampleNumber);

			});

		});

		if(messageOne == 13 && messageThree == 1, { //activate trigger record

			switch(~triggerRecordingStatusIndicator[sampleNumber], 1, {

				if(~triggerRecordingSetToClear[sampleNumber] == 1, {

					~triggerRecordingSetToClear[sampleNumber] = 0;
					~triggerRecordingStatusIndicator[sampleNumber] = 0;

					~gridLeds[13 + (ledOffsets[sampleNumber] * 16)] = 0;
					~updateGridLeds.value;

					post("Trigger Recorder" + sampleNumber + "released from PreSet State");

				}, {

					~recordTriggerTimeBus[sampleNumber].get({arg index;

						~triggerRecordingList[sampleNumber][0].put(4, index);

						Synth("Trigger_Time_Reset_Impulses", [\outputBus, ~triggerTimeResetImpulseBusses[sampleNumber]]);

					});

					~triggerRecordingStatusIndicator[sampleNumber] = 0;

					~gridLeds[13 + (ledOffsets[sampleNumber] * 16)] = 0;
					~updateGridLeds.value;

					postln("Stopping Recording of Sample" + sampleNumber + "triggers");


					if(~triggerPlaybackPreSet[sampleNumber] == 1, { //if playback PreSet is on

						~triggerPlaybackFunction[sampleNumber].value;

						~triggerPlaybackStatusIndicator[sampleNumber] = 1;

						~triggerPlaybackPreSet[sampleNumber] = 0;

						postln("Playing Trigger Recording from PreSet State on Track" + sampleNumber);

					});

				});

			}, 0, {

				Synth("Trigger_Time_Reset_Impulses", [\outputBus, ~triggerTimeResetImpulseBusses[sampleNumber]]);

				~triggerRecordingStatusIndicator[sampleNumber] = 1;
				~triggerRecordingSetToClear[sampleNumber] = 1;

				~gridLeds[13 + (ledOffsets[sampleNumber] * 16)] = 15;
				~updateGridLeds.value;

				postln("Starting Recording of Sample" + sampleNumber + "triggers");

			});

		});

		if(messageOne == 14 && messageThree == 1, { //play triggers

			switch(~triggerPlaybackStatusIndicator[sampleNumber], 0, {

				switch(~triggerRecordingStatusIndicator[sampleNumber], 1, {

					~triggerPlaybackPreSet[sampleNumber] = 1;

					~gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 15;
					~updateGridLeds.value;

					postln("Trigger Playback Pre Set on Track" + sampleNumber);

				}, 0, {

					~triggerPlaybackFunction[sampleNumber].value;

					~triggerPlaybackStatusIndicator[sampleNumber] = 1;

					~gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 15;
					~updateGridLeds.value;

					~triggerPlaybackPreSet[sampleNumber] = 0;

					postln("Playing Trigger Recording on Track" + sampleNumber);

				});

			}, 1, {

				~triggerPlaybackTempoClocks[sampleNumber].clear;
				~triggerPlaybackPositionCount[sampleNumber] = 0;

				~triggerPlaybackStatusIndicator[sampleNumber] = 0;

				~gridLeds[14 + (ledOffsets[sampleNumber] * 16)] = 0;
				~updateGridLeds.value;

				postln("Stopping Position Playback on Track " + sampleNumber);

			});

		});


	}; //end non recording


	if(~arcDevicePort.notNil, {

		OSCFunc.newMatching( // arc funtionality
			{ arg message, time, addr, recvPort;

				var arcFunctions = {arg name, messageOne, messageTwo, ledLevel = 15;
					name.change(messageTwo);
					name.sendChange;
					~updateArcLeds.value(messageOne, name.arcLedValue, ledLevel);
				};

				if(addr.port == ~arcDevicePort, {
					switch(~arcSelectionRight[0], 1, { //hidden volume mixer

						switch(message[1], 0, {
							arcFunctions.value(~volumes[0], 0, message[2], 5);
						}, 1, {
							arcFunctions.value(~volumes[1], 1, message[2], 5);
						}, 2, {
							arcFunctions.value(~volumes[2], 2, message[2], 5);
						}, 3, {
							arcFunctions.value(~volumes[3], 3, message[2], 5);
						});

					}, 0, {

						switch(message[1], 0, {
							arcFunctions.value(~pairs[~arcSelectionLeft[1]][0], 0, message[2]);
						}, 1, {
							arcFunctions.value(~pairs[~arcSelectionLeft[1]][1], 1, message[2]);
						}, 2, {
							arcFunctions.value(~pairs[~arcSelectionRight[1]][0], 2, message[2]);
						}, 3, {
							arcFunctions.value(~pairs[~arcSelectionRight[1]][1], 3, message[2]);
						});

					});
				});

		}, "/monome/enc/delta");

	});

	//create playback synths

	for(0, 3, {arg i;

		~playbackSynth[i] = Synth("Sample_Playback_Synth", [\rate, 0, \sampleBuffer, ~sampleStorageBuffer[i], \startValue, ~currentPlaybackStart[i], \restartPhasor, ~playbackPhasorNewPositionTrigger[i], \ledPhasorOutput, ~playRowLedBus[i], \clickStopTrigger, ~clickStopTriggerBus[i], \volume, ~volumeDefault, \maxEnvelopeVolume, ~maxEnvelopeVolume]);

	});

	//create trigger timer synth
	for(0, 3, {arg sampleNumber;

		~recordTriggerTimeSynth[sampleNumber] = Synth("Trigger_Time_Distance_Synth", [\outputBus, ~recordTriggerTimeBus[sampleNumber], \triggerInputBus, ~triggerTimeResetImpulseBusses[sampleNumber]]);

	});

	postln("Creating Sample Playback Synths 0 - 3");

	if(~arcDevicePort.notNil, {
		~pairs = [

			[ArcParameter.new("Sample Zero Cutoff", 20, 20000, 1, 2, 20000, ~playbackSynth[0], \cutoff, 0), ArcParameter.new("Sample Zero Resonance", 0.01, 1, 500, 1, 1, ~playbackSynth[0], \resonance, 0)], [ArcParameter.new("Sample Zero FM Speed", 0, 500, 5, 2, 0, ~playbackSynth[0], \fmSpeed, 0), ArcParameter.new("Sample Zero FM Depth", 0, 20, 25, 2, 0, ~playbackSynth[0], \fmDepth, 0)], [ArcParameter.new("Sample Zero Loop Start", 0, 1, 100, 2, 0, ~playbackSynth[0], \loopStart, 0), ArcParameter.new("Sample Zero Loop End", 0.001, 1, 100, 2, 1, ~playbackSynth[0], \loopLength, 0)],

			[ArcParameter.new("Sample One Cutoff", 20, 20000, 1, 2, 20000, ~playbackSynth[1], \cutoff, 0), ArcParameter.new("Sample One Resonance", 0.01, 1, 500, 1, 1, ~playbackSynth[1], \resonance, 0)], [ArcParameter.new("Sample One FM Speed", 0, 500, 5, 2, 0, ~playbackSynth[1], \fmSpeed, 0), ArcParameter.new("Sample One FM Depth", 0, 20, 25, 2, 0, ~playbackSynth[1], \fmDepth, 0)], [ArcParameter.new("Sample One Loop Start", 0, 1, 100, 2, 0, ~playbackSynth[1], \loopStart, 0), ArcParameter.new("Sample One Loop End", 0.001, 1, 100, 2, 1, ~playbackSynth[1], \loopLength, 0)],

			[ArcParameter.new("Sample Two Cutoff", 20, 20000, 1, 2, 20000, ~playbackSynth[2], \cutoff, 0), ArcParameter.new("Sample Two Resonance", 0.01, 1, 500, 1, 1, ~playbackSynth[2], \resonance, 0)], [ArcParameter.new("Sample Two FM Speed", 0, 500, 5, 2, 0, ~playbackSynth[2], \fmSpeed, 0), ArcParameter.new("Sample Two FM Depth", 0, 20, 25, 2, 0, ~playbackSynth[2], \fmDepth, 0)], [ArcParameter.new("Sample Two Loop Start", 0, 1, 100, 2, 0, ~playbackSynth[2], \loopStart, 0), ArcParameter.new("Sample Two Loop End", 0.001, 1, 100, 2, 1, ~playbackSynth[2], \loopLength, 0)],

			[ArcParameter.new("Sample Three Cutoff", 20, 20000, 1, 2, 20000, ~playbackSynth[3], \cutoff, 0), ArcParameter.new("Sample Three Resonance", 0.01, 1, 500, 1, 1, ~playbackSynth[3], \resonance, 0)], [ArcParameter.new("Sample Three FM Speed", 0, 500, 5, 2, 0, ~playbackSynth[3], \fmSpeed, 0), ArcParameter.new("Sample Three FM Depth", 0, 20, 25, 2, 0, ~playbackSynth[3], \fmDepth, 0)], [ArcParameter.new("Sample Three Loop Start", 0, 1, 100, 2, 0, ~playbackSynth[3], \loopStart, 0), ArcParameter.new("Sample Three Loop End", 0.001, 1, 100, 2, 1, ~playbackSynth[3], \loopLength, 0)],

		];

		//master volume parameters

		~volumes = [ArcParameter.new("Sample Zero Volume", 0, 1, 100, 2, ~volumeDefault, ~playbackSynth[0], \volume, 0), ArcParameter.new("Sample One Volume", 0, 1, 100, 2, ~volumeDefault, ~playbackSynth[1], \volume, 0), ArcParameter.new("Sample Two Volume", 0, 1, 100, 2, ~volumeDefault, ~playbackSynth[2], \volume, 0), ArcParameter.new("Sample Three Volume", 0, 1, 100, 2, ~volumeDefault, ~playbackSynth[3], \volume, 0)];

	});

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

	if(~arcDevicePort.notNil, {
		~updateArcLeds = {arg encoderNumber, ledValue, ledLevel = 15;

			var encoderTemporaryArray = Array.fill(64, { arg index;
				if(index <= ledValue, { ledLevel }, { 0 });
			});

			~arc4.ringmap(encoderNumber, encoderTemporaryArray);

		};
	});

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

	if(~arcDevicePort.notNil, {
		~gridLeds[10 + (0 * 16)] = 15;
		~gridLeds[11 + (0 * 16)] = 7;

		//initialize arc leds

		~updateArcLeds.value(0, ~pairs[0][0].arcLedValue);
		~updateArcLeds.value(1, ~pairs[0][1].arcLedValue);
		~updateArcLeds.value(2, ~pairs[1][0].arcLedValue);
		~updateArcLeds.value(3, ~pairs[1][1].arcLedValue);
	});

	//trigger playback functions

	for(0, 3, {arg i;

		~triggerPlaybackFunction[i] = {
			var count = ~triggerPlaybackPositionCount[i];

			~triggerPlaybackTempoClocks[i].sched(0, {

				~recordableButtons.value(~triggerRecordingList[i][count][0], ~triggerRecordingList[i][count][1], ~triggerRecordingList[i][count][2], ~triggerRecordingList[i][count][3]);

				count = ((count + 1) % ~triggerRecordingList[i].size);

				~triggerRecordingList[i][count][4];

			});

		};

	});

	//monitor for play row leds
	~playRowLedMonitor = Task({
		var interval = 0.01;
		var playRows = [1, 3, 5, 7];

		loop {

			for(0, 3, {arg i;

				~playRowLedBus[i].get({ arg value;

					if((value.asInteger != ~currentPlayLed[i]) && (value.asInteger >= 0), {
						~currentPlayLed[i] = value.asInteger;

						for(0, 15, {arg x;
							~gridLeds[x + (playRows[i] * 16)] = 1;
						});

						~gridLeds[value.asInteger + (playRows[i] * 16)] = 15;

					});

				});

			});

			~updateGridLeds.value;

			interval.yield;
		}

	});

	~playRowLedMonitor.play;


}); //end wait for boot

)
