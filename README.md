# Animalation-SC

Animalation - written in SuperCollider.   
Animating the Animal.  
For Grid 128 and Arc 4.  

Animalation is a four-track live-input live-sampler, with mlr style position   
triggering, trigger recording/playback, reverse, low-pass filtering with   
cutoff and resonance, fm modulation, and modulatable loop start and length.   
It allows you to record whatever is coming into an input channel on your   
audio interface (or built-in microphone) and play it back instantly.  
  
  
Animalation has only been tested on Trisquel GNU/Linux, but I don't see   
any reason it shouldn't work on other GNU/Linux distributions or Windows/Mac.   
Windows/Mac, using your interface should be as simple as plugging it in and turning it on.  
GNU/Linux, get your audio interface working with jack.   
For me I use the command 'jackd -d alsa -d hw:Ultra' to get my Fast-Track Ultra to be recognized.  
  
There are some parameters that can be set by the user.  
These parameters are designated and explained in the user control area  
which is desiginated at the top of the code in SuperCollider.  

If you would like to use Animalation without an Arc 4, you can set
an option in the user control area to disable all arc features.
  
  
Preperation:  
  
SuperCollider needs to have access to two things:  
  
The MonoM classes. These can be downloaded here : github.com/catfact/monom/archive/master.zip  
The ArcParameter.sc class included in the Animalation download folder.  
  
Once the MonoM classes are downloaded, they should be extracted from the zip folder.  
  
Now, open SuperCollder. From the menu bar go to Edit --> Preferences.  
Under the preferences, click on Interpreter.  
Under the Interpreter options, we need to include the MonoM folder and  
the Animalation folder.  
To include these, click on the green plus symbol next to the include  
text box. This will allow you to browse to the locations of the folders  

You can click ok, then click ok in the pop up box.  
Now you need to recompile the class library. This is simple.  
You can either close and reopen SuperCollider, or go to   
Language -- > Recompile Class Library in the menu bar,  
or simply press control-shift-l (l as in larry).   
  
  
Basic Usage:  
  
First the basic commands you will need for SuperCollider.  

First you must start the sound server. This can be done in one of three ways:
1. Press Ctrl(Cmd)+Enter on the first line in the program, where is says "s.boot;"
2. Press Ctrl(Cmd)+b
3. Go to Server > Boot Server
  
Click anywhere below the first line of code and press control-enter. This will start Animalation.  
If you want to clear what is in the post window at any time, the command is control-shift-p.  
Click control-. (that's the control key and the period key) to completely stop Animaltion.  
All samples will be lost when control-. is pressed.  
  
IMPORTANT: To avoid confusion with what is written in the post window in SuperCollider,   
the first track will be called track 0, the second track will  
be called track 1, the third track will be called track 2, and   
the fourth track will be called track 3.  
IF YOU ARE CONFUSED ABOUT WHAT TRACK I AM REFERRING TO BELOW,  
THINK OF THIS!  
  
Buttons on the grid are numbered starting from 0.  
The x-axis goes from 0 to 15 (the columns).  
The y-axis goes from 0 to 7 (the rows).  
  
Each track is two rows.   
The top row has various controls, and the bottom row is the playback position row.  
  
The controls will be explained as if we are working on track 0,  
but they apply to all four tracks in the same way.  
  
To begin, press the record button (0, 15).   
This will begin recording whatever is playing into the input on your audio interface.  
When you are finished, press the record button again to stop recording.  
  
To play the sample you recorded, press the play button (0, 9).  
The sample will continue playing as long as this button is on.  
You can record a new sample on the same track while the old sample is playing.  
If you record a new sample on the same track while the old sample is playing,  
it will begin as soon as you finish recording the new sample.  
  
To play the sample backwards, press the reverse button (0, 8).  
To play the sample forwards again, press the reverse button again.  
  
You can change the pitch with the keys (0, 0) through (0, 7).  
The pitches you can select are:  
  
(0, 0) - two octaves down.  
(0, 1) - one octave down plus a fourth.  
(0, 2) - one octave down.  
(0, 3) - a fourth down.  
(0, 4) - unison (the default pitch, the original pitch of the recorded sample.  
(0, 5) - a fifth up.  
(0, 6) - one octave up.  
(0, 7) - an octave and a fifth up.  
  
The keys in the second row ((1, 0) through (1, 15)) are used to change the  
current position of the sample. You will see the current position of the sample  
displayed by the leds on the grid. Click a key to jump to the position.  
  
You can record and playback realtime changes in the position row (the second row,   
mentioned in the previous paragraph), changes of pitch, changes of direction,   
and changes of the playback state. This is called trigger recording.  
  
Trigger recording can only be done monophonically.  
  
To record triggers, press the record triggers key (0, 13).  
The recording will begin when the first key is pressed.  
To stop the recording, press the record triggers key again.  
  
To playback the trigger recording, press the trigger playback key (0, 14).  
To stop the trigger playback, press the trigger playback key again.     
  
Trigger playback can be pre-set to begin as soon as trigger recording ends.  
Trigger playback can be pre-set by pressing the trigger playback button  
before the end of the trigger recording.  
  
Example:   
Press the record trigger key to get ready to record triggers.  
Begin recording by pressing a key to change the loop position.  
Play however much more you desire.  
Pres the playback trigger key to preset playback.  
End the trigger recording by pressing the record trigger button again.  
Playback of the triggers will begin instantly.  
  
Playback does not have to be pre-set as the last action before ending trigger recording,  
it can be pre-set anytime after the record trigger button is pressed the first time  
and before it is released to end the trigger recording.  
  
    
Arc control and the Arc Selection Matrix:  
  
  
The arc 4 can control various parameters of the playback samples.  
The arc encoders are numbered 0 to 3 from left to right.  
  
By default, the arc encoders will be controlling filter cutoff, filter resonance,  
fm speed, and fm depth respectively (all on track 0).  
  
Parameters are grouped in pairs.   
You can select a pair of parameters for the left side  
of the arc (encoders 0 and 1) and a pair for the right side of the arc (encoders 2 and 3).  
  
The pairs for each track are:  
  
10 - filter cutoff and filter resonance  
11 - fm speed and fm depth  
12 - loop start and loop length  
  
Changing the parameters that the arc is controlling is done with the arc selection matrix.  
  
The arc selection matrix is keys 10 through 12 in each of the   
top rows of the tracks (rows 0, 2, 4, and 6).  
So, all the key positions included in the arc selection matrix are:  
(0, 10), (0, 11), (0, 12) for track 0  
(2, 10), (2, 11), (2, 12) for track 1  
(4, 10), (4, 11), (4, 12) for track 2  
(6, 10), (6, 11), (6, 12) for track 3  
  
To select the parameters for the left side of the arc (encoders 0 and 1), press a key in   
the arc selection matrix. You will see the value of the newly selected parameter displayed  
by the arc leds.  
  
Example:  
Let's say I want to control filter cutoff and resonance of track 1 on   
the left side of the arc (encoders 0 and 1).  
I would press the key (2, 10).  
  
To select the parameters for the right side of the arc (encoders 2 and 3),   
you must first press and hold the key of the currently selected parameter for  
the left side of the arc. Then, press any other key in the arc selection matrix to   
select that parameter pair for control with the right side encoders (encoders 2 and 3).  
  
Example:  
Let's say I want to control the fm speed and fm depth of track 2 on the   
right side of the arc (encoders 2 and 3).  
First, I must press and hold the key of the currently selected parameter pair  
for the left side of the arc (from the example above that would be key (2, 10)).  
Now, I can select the fm speed and fm depth pair for the right side of the arc  
by pressing the key (4, 11).   
  
You may notice that the leds around the arc look different when you are   
holding both the keys for the left and right side parameter selection.  
  
This is because the master volume mixer for controlling the overall   
volume of each track is accessed by holding down both the key of the   
currently selected parameter pair for the left side of the arc  
and the key for the currently selected parameter pair for the right  
side of the arc. The volume for each track is controlled by each  
encoder respectively (encoder 0 controls the volume for track 0,  
encoder 1 controls the volume for track 1 etc.)  
  
Example:  
Lets say I want to lower the overall volume of track 3.  
First I press and hold the key of the currently selected parameter pair   
for the left side of the arc (currently that is (2, 10)).  
Then I press and hold the key of the currently selected parameter pair  
for the right side of the arc (currently that is (4, 11).  
Now, I can adjust the volume of track 3 by rotating encoder 3.  
I can release one of the keys and the volume mixer will be exited.  

The volume mixer can be held on after the left and right arc selection 
buttons are held down for a specified period of time by changing the 
~volumeMixerHoldTime user option from nil to a number. For example,
changing ~volumeMixerHoldTime to 1 will cause the volume mixer
to be held on after holding the left and right arc selection 
buttons for 1 second. 

To leave the held volume mixer press the left and right arc selection 
buttons again.
  
Long-Term Goals:  
  
Create version for grid 64 and 256.  
Redo length formula so length of inter-sample loop is consistent no matter the starting point.  
Polyphonic trigger recording.  
Improve trigger recording timing and accuracy.  
Removing hardcoding mono input
Add non-varibright support
  
There could be a potential runtime bug from using "Recording/Playback_Reset_Trigger" for multiple functions.  
