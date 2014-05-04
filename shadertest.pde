// Zeitgeber v0.0001

// TODO
// Stream parameters should include "entrainability", d.h., probability of phase and period resetting
// wrt other streams or external events
// Perhaps multiple entrainabilities/stream ... for other streams, for camera events ...

import java.util.Random;

import processing.video.*;

// BIG TODO
// - Rewrite in terms of millis, not frames -- less aliasing etc
// Encapsulate oscillator
// Encapsulate zeitgeber too?

// TODO
// Check Blue Notebook, gegenüber QS-Dia-Bermerkungen, for latest
// including antiphase phase shift, phase delay vs advance (takes quickest route toward entrainer),
// gain dependence of phase shift (maybe a phase angle * gain term in the response curve)
// plus, non-pulse (ambient) zeitgeber effects on period and gain (d.h. from environmental sensors)


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


Random theRNG; // Initialized in setup()

int halfbeat;
int beat;
	// In milliseconds. Actual half-beat is .5 less
	// To see if an oscillator is on beat we test
	// abs( millis() % ( period + beat ) - phase ) < halfbeat
	// if == 0 we're exactly at the center of the beat
	// otherwise need a half-beat radius around that exact center
	// TODO: Would it be more intuitive to use <= halfbeat and have beat be 2*halfbeat + 1?

PShader shadr;

int nOscillators;
Oscillator[] oscillators;

void setup() {
	size( 720, 480, P2D );
	colorMode( RGB, 1.0 );
	frameRate( 60 );
	noStroke();

	theRNG = new Random(/* long seed */); // RNG for noise terms

	JSONObject config = loadJSONObject( "config.json" );

	halfbeat = config.getInt( "beatRadius" );
	beat = halfbeat * 2 - 1;

	// Shader setup
	shadr = loadShader( "shaders/" + config.getString( "shader" ) + ".glsl" );
	shadr.set( "resolution", float(width), float(height) );
	shadr.set( "halfbeat", halfbeat );
	shadr.set( "beat", beat );

	// Configure the oscillators

	JSONArray oscParams = config.getJSONArray( "oscillators" );

	nOscillators = oscParams.size();
	oscillators = new Oscillator[nOscillators];

	for ( int i = 0; i < nOscillators; ++i ) {
		JSONObject osc = oscParams.getJSONObject( i );

		string streamHandle = osc.getString( "stream" );
		int period = osc.getInt( "period" );
		double phase = osc.getFloat( "phase" );
		double gain = osc.getFloat( "gain" );
		JSONArray blnc = osc.getJSONArray( "balance" );
		double periodRCH = osc.getFloat( "periodRC_hysteresis" );
		double gainRCH = osc.getFloat( "gainRC_hysteresis" );

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
									balance
									periodRCH,
									gainRCH
								);
	}
}

void draw() {
	background( color(0.,0.,0.) );

	// Once a beat, check to see if any oscillators are on beat
	if ( millis() % beat == 0 ) {
		for ( int i = 0; i < nOscillators; ++i ) {
			if ( oscillators[i].onBeat() ) {
				// TODO See if the other oscillators want to entrain to this one
			}
		}
	}

	// TODO: Handle sensor events

	// Update shader uniforms with texture frame data and oscillator params
	for ( int i = 0; i < nOscillators; ++i ) {
		oscillators[i].setShader(shadr);
	}

	shadr.set( "time", millis() );

	shader(shadr);
	fill( color(1.,1.,1.) ); // gives us the option of * vertColor in frag shader
	rect( 0, 0, width, height );
}

// Movie events
void movieEvent( Movie m ) {
	m.read();
}
void stop() {}


// Oscillator-related


double clamp( double x, double a, double b ) {
	return x < a ? a : x > b ? b : x;
}

double gnoise( double mean, double sd ) {
	// Clamping at 6 sigma should not introduce too much squaring ...
	return mean + sd * clamp( theRNG.nextGaussian(), -6, 6 );
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

	double gain; // 1-based, i.e., a coefficient
	PVector balance; // RGB for beat expression

	// Response curve hysteresis terms: > 0 means latency on descending values
	double periodRC_hysteresis, gainRC_hysteresis;

	Oscillator() { }

	Oscillator(		int id_, Movie s_,
					int period_, double phase_,
					double gain, PVector balance_,
					double perRCh, double gainRCh ) {

		id = id_;
		s = s_;

		period = period_;
		phase = int(phase_ * period); // Map phase to period
		
		gain = gain_;
		balance = balance_;
		
		periodRC_hysteresis = perRCh;
		gainRC_hysteresis = gainRCh;
	}

	void setShader( PShader sh ) {
		PImage frame = s;
		sh.set( "stream" + id, frame );
		sh.set( "period" + id, period );
		sh.set( "phase" + id, phase );
		sh.set( "gain" + id, gain );
		sh.set( "balance" + id, balance );
	}

	boolean onBeat() {
		return abs( millis() % ( period + beat ) - phase ) < halfbeat;
			// + beat to handle edge-of-period half-beat problem
	}
}



// FIXME WHAT FOLLOWS IS OLD AND WILL BE TAKEN OUT OR HARVESTED FOR SCRAP

void updateOscillators() {
	final double a = 1.;
	final double b = 0.;

	// Variance of underlying normal Y = log(X) for lognormal X
	double sigma = cos(a * (double)millis()/1000. ) + b;

	for ( int i = 0; i < N_OSC; ++i ) {
		// TODO Adjust period
		// - Symmetric period-length oscillator for each stream 
		//   -- deterministic oscillation + Gaussian noise term

		// maybePerturbPeriod ??

		// TODO Maybe we need baseline periods, and perturbed periods anneal to baseline
		// Or rather, baseline period range -- oscillation stays w/i range, perturbance
		// kicks it out ( e.g. via entrainment )

		// Maybe reset phase or entrain to one of the other streams
		int neighbor;
		if ( phaseReset(i) )
			phase[i] = millis() % period[i];
		else {
			neighbor = maybeEntrain(i);
			if ( neighbor > -1 ) {
				phase[i] = millis() % period[i];
				double weight = entrainability[i];
				period[i] = round( period[neighbor] * weight + period[i] * (1 - weight) );
			}
		}

		// Maybe perturb the gain, or anneal
		double pert = gainPerturbance(i);
		if ( pert > 0 )
			gain[i] += pert;
		else if ( gain[i] > gainBaseline[i] ) {
			// simulated annealing ... do we need a per-stream annealing rate?
		}
	}
}

boolean phaseReset( int streamId ) {
	return false;
	// check sensors, maybe also small probability of randomly resetting?
}

int maybeEntrain( int streamId ) {
	// Check neighbors. If any is on the beat, maybe entrain
	for ( int i = 1; i < N_OSC; ++i ) {
		int neighbor = (streamId + i) % N_OSC;
		if ( onTheBeat(neighbor) ) {
			if ( theRNG.nextDouble() < entrainability[i] )
				return neighbor;
		}
	}
	return -1;
}

boolean onTheBeat( int streamId ) {
	return abs( millis() % ( period[streamId] + beat ) - phase[streamId] ) < halfbeat;
		// + beat to handle the edge-of-period half-beat problem
}

double gainPerturbance( int streamId ) {
	return 0.;
	// check sensors, maybe also random noise
}
