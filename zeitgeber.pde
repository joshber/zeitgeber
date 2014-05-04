// Zeitgeber v0.0001

import java.util.Random;

import processing.video.*;

// Longer-term TODO --
// Clean up float / int thing in oscillator members

// ****** TODO --
// Parameterize beat diameter per oscillator
// Along with gain threshold
// That way, with ease in / ease out, you could have a single oscillator model
// that worked both as a pulse and a sine
// D.h., when beat diamter == period, it's a sine

// Two kinds of zeitgeber, ambient and event (pulse -- i.e., sudden sensor event)

// Period and gain change only in response to ambient zeitgeber, something like Temperature--
// Could be noise in the room or total sensor activity ...
// Period and gain have response curves, something like Perlin's Hermite + Gaussian noise term

// Phase is the only thing that responds to pulse zeitgeber
// Again, a phase response curve -- logistic-type Hermite + Gaussian noise term


// Ok, from the latest notes (19.4.14)--

// millis() % 41 (pulsewidth) check to see if any oscillators are on the beat
// If so, they broadcast to others, which may entrain according to a phase response curve
// Maximum phase response should be at antiphase from the on-beat oscillator (cf Czeisler and Gooley 2007)
// with phase delay (retardation) if it's before antiphase,
// phase advance if it's after
// -- This is not a total resetting, but a phase shift in the (nearer) *direction* of entrainment
// ZUDEM: Phase response is gain-dependent. Maybe a phase angle * gain term in the response curve
// Or rather, gain RATIO, that is:
// phase angle * Entrainer-Gain / Entrainee-Gain

// Period and gain--
// each need two dose response curves for ambient zeitgeber, one ascending, one descending,
// to get hysteresis
// Keep it simple: (x + C), where C is the hysteresis term -- C > 0 means latency on descent
// This can be parameterized in the constructor, oder?

// All response curves also have a Gaussian error term


Random theRNG; // For generating noise terms

int halfbeat;
int beat;
	// In milliseconds. Actual half-beat is .5 less
	// To see if an oscillator is on beat we test
	// abs( millis() % ( period + beat ) - phase ) < halfbeat
	// if == 0 we're exactly at the center of the beat
	// otherwise need a half-beat radius around that exact center
	// TODO: Would it be more intuitive to use <= halfbeat and have beat be 2*halfbeat + 1?

PShader shadr;

float gainThreshold;

int nOscillators;
Oscillator[] oscillators;

void setup() {
	size( 720, 480, P2D );
	colorMode( RGB, 1.0 );
	noStroke();

	theRNG = new Random(/* long seed */);

	loadConfig();
}

void draw() {
	background( color(0.,0.,0.) );

	// Once a beat, check to see if any oscillators are on beat
	if ( millis() % beat == 0 ) {
		for ( int i = 0; i < nOscillators; ++i ) {
			double onBeat = oscillators[i].onBeat();
			if ( onBeat > 0 ) {
				// TODO See if the other oscillators want to entrain to this one
			}
		}
	}

	// TODO: Handle sensor events

	// Update shader uniforms with texture frame data and oscillator params
	for ( int i = 0; i < nOscillators; ++i ) {
		oscillators[i].setShader(shadr);
	}

	shadr.set( "time", float( millis() ) );
		// Passed as float bc GLSL < 3.0 can't do modulus on ints

	shader(shadr);
	fill( color(1.,1.,1.) ); // gives us the option of * vertColor in frag shader
	rect( 0, 0, width, height );
}

// Movie events
void movieEvent( Movie m ) {
	m.read();
}
void stop() {}

//
// Control and delegation

void keyPressed() {
	if ( key == 'r' || key == 'R' ) {
		reloadConfig();
	}
}

void reloadConfig() {
	// TODO: Clean up from previous iteration to minimize memory leaks?
	loadConfig();
}

void loadConfig() {
	JSONObject config = loadJSONObject( "config.json" );

	frameRate( config.getFloat( "fps" ) );

	halfbeat = config.getInt( "beatRadius" );
	beat = halfbeat * 2 - 1;

	gainThreshold = config.getFloat( "gainThreshold" );
	
	// Shader setup
	shadr = loadShader( "shaders/" + config.getString( "shader" ) + ".glsl" );
	shadr.set( "resolution", float(width), float(height) );

	// At the moment, beat diameter is fixed -- But could be made mutable
	// Passed as floats bc GLSL < 3.0 can't do mixed float-int arithmetic
	shadr.set( "halfbeat", float(halfbeat) );
	shadr.set( "beat", float(beat) );

	shadr.set( "threshold", gainThreshold );

	//
	// Configure the oscillators

	JSONArray oscParams = config.getJSONArray( "oscillators" );

	nOscillators = oscParams.size();
	oscillators = new Oscillator[nOscillators];

	for ( int i = 0; i < nOscillators; ++i ) {
		JSONObject osc = oscParams.getJSONObject( i );

		String streamHandle = osc.getString( "stream" );
		int period = osc.getInt( "period" );
		float phase = osc.getFloat( "phase" );
		float gain = osc.getFloat( "gain" );
		JSONArray blnc = osc.getJSONArray( "balance" );
		float periodRCH = osc.getFloat( "periodRC_hysteresis" );
		float gainRCH = osc.getFloat( "gainRC_hysteresis" );

		// FIXME Will this work? Or do we need to get them as JSONObjects first?
		PVector balance = new PVector( blnc.getFloat( 0 ), blnc.getFloat( 1 ), blnc.getFloat( 2 ) );

		// Start the stream
		Movie s = new Movie( this, "streams/" + streamHandle + ".mov" );
		s.loop();

		oscillators[i] = new Oscillator(
									i,			// id
									s,			// video stream
									period,
									phase,
									gain,
									balance,
									periodRCH,
									gainRCH
								);
	}
}

//
// Oscillator-related

double clamp( double x, double a, double b ) {
	return x < a ? a : x > b ? b : x;
}

double gnoise( double mean, double sd ) {
	// Clamping at 6 sigma should not introduce too much squaring ...
	return mean + sd * clamp( theRNG.nextGaussian(), -6., 6. );
}

// Perlin's Hermite 6x^5 - 15x^4 + 10x^3
double smootherstep( double a, double b, double x ) {
    // Scale, and clamp x to 0..1 range
    x = clamp( (x - a) / (b - a), 0., 1. );
    // Evaluate polynomial
    return x*x*x * (x * ( x*6 - 15 ) + 10);
}

class Oscillator {
	int id;

	Movie s;

	int period, phase; // in ms

	float gain; // 1-based, i.e., a coefficient
	PVector balance; // RGB for beat expression

	// Response curve hysteresis terms: > 0 means latency on descending values
	float periodRC_hysteresis, gainRC_hysteresis;

	Oscillator() { }

	Oscillator(		int id_, Movie s_,
					int period_, float phase_,
					float gain_, PVector balance_,
					float perRCH, float gainRCH
				) {
		id = id_;
		s = s_;

		period = period_;
		phase = int( phase_ * period ); // Map phase to period
		
		gain = gain_;
		balance = balance_;
		
		periodRC_hysteresis = perRCH;
		gainRC_hysteresis = gainRCH;
	}

	void setShader( PShader sh ) {
		PImage frame = s;
		sh.set( "stream" + id, frame );

		// Passed as floats bc GLSL < 3.0 can't do modulus on ints
		sh.set( "period" + id, float(period) );
		sh.set( "phase" + id, float(phase) );

		sh.set( "gain" + id, gain );
		sh.set( "balance" + id, balance );
	}

	double onBeat() {
		// Returns in interval [0,1] -- 0 off-beat, 1 at center of beat
		return clamp( float( halfbeat - abs( millis() % ( period + beat ) - phase ) ), 0., float(halfbeat) )
				/ float(halfbeat);
			// period + beat to handle edge-of-period half-beat problem
	}
}