ArcParameter {
	var name, minimum, maximum, scale, expoentialFactor, value, destination, argument, iterations;

	*new { arg parameter_name, minimum_value, maximum_value, scale_divisor, exponential_factor, default_value, destination_variable, argument_to_set, number_of_iterations;
		^super.new.init(parameter_name, minimum_value, maximum_value, scale_divisor, exponential_factor, default_value, destination_variable, argument_to_set, number_of_iterations)
	}

	init { arg parameter_name, minimum_value, maximum_value, scale_divisor, exponential_factor, default_value, destination_variable, argument_to_set, number_of_iterations;
		name = parameter_name;
		minimum = minimum_value;
		maximum = maximum_value;
		scale = scale_divisor;
		expoentialFactor = exponential_factor;
		value = default_value;
		destination = destination_variable;
		argument = argument_to_set;
		iterations = number_of_iterations;
	}


	currentValue {
		(name + " = " + value).postln;

		^value;
	}

	change { arg input;

		if(input > 0, {
			value = value + pow((input / scale), expoentialFactor);
		});

		if(input < 0, {
			value = value - pow((input / (-1 * scale)), expoentialFactor);

		});

		if((value <= minimum), {
			value = minimum;
		});

		if((value >= maximum), {
			value = maximum;
		});

		(name + " = " + value).postln;

		^(name + " = " + value);
	}


	sendChange { //should this be a switch? can't be because of > check

		if(iterations == -1, {
			destination.value(value);
		});

		if(iterations == 0, {
			destination.set(argument, value);
		});

		if(iterations > 0, {
			for(0, iterations, { arg i;
				destination[i].set(argument, value);
			});
		});

	}

	arcLedValue {

		^LinLin.kr(value, minimum, maximum, 0, 63);

	}


}


