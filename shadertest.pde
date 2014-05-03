// Zeitgeber v0.0001

// TODO
// Stream parameters should include "entrainability", d.h., probability of phase and period resetting
// wrt other streams or external events
// Perhaps multiple entrainabilities/stream ... for other streams, for camera events ...

import java.util.Random;

import processing.video.*;

final int SHADER_ID = 0;

final int N_OSC = 3;

final int halfbeat = 20; // in ms ... FIXME should this be 20 or 21?
final int beat = 41;

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


double clamp( double x, double a, double b ) {
	return x < a ? a : x > b ? b : x;
}

Random theRNG; // Initialized in setup()

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

PShader shadr;
Oscillator[] oscillators = new Oscillator[N_OSC];

void setup() {
	size( 720, 480, P2D );
	colorMode( RGB, 1.0 );
	frameRate(60);
	noStroke();

	theRNG = new Random(/* long SEED? */);

	shadr = loadShader( "shaders/frag" + SHADER_ID + ".glsl" );

	for ( int i = 0; i < N_OSC; ++i ) {
		Movie s = new Movie( this, "streams/stream" + i + ".mov" );
		s.loop();

		// TODO Get oscillator parameters from a configuration JSON

		oscillators[i] = new Oscillator(
									i,							// id
									s,							// video stream
									1000,						// period
									0.,							// phase
									1.2,						// gain
									new PVector(1.5,1.,1.),		// balance
									1.,							// period RC hysteresis
									1.							// gain RC hysteresis
								);
	}

	shadr.set( "resolution", float(width), float(height) );
	shadr.set( "halfbeat", halfbeat );
	shadr.set( "beat", beat );
}

void draw() {
	background( color(0.,0.,0.) );

	// Once a beat, check to see if any oscillators are on beat
	if ( millis() % beat == 0 ) {
		for ( int i = 0; i < N_OSC; ++i ) {
			if ( oscillators[i].onBeat() ) {
				// TODO See if the other oscillators want to entrain to this one
			}
		}
	}

	// TODO
	// Handle sensor events

	for ( int i = 0; i < N_OSC; ++i ) {
		oscillators[i].setShader(shadr);
	}

	shadr.set( "time", millis() );

	shader(shadr);
	fill( color(1.,1.,1.) ); // gives us option of * vertColor in frag shader
	rect( 0, 0, width, height );
}

// Movie events
void movieEvent( Movie m ) {
	m.read();
}
void stop() {}


// Oscillator-related


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



//double lognormal( double sigma ) {
//	return exp( sigma * theRNG.nextGaussian() );
//}



	//   -- maybe a Gaussian whose mean oscillates above and below zero
	//   -- or a lognormal where sigma oscillates between .1 and 10 and flips sign whenever sigma
	//      passes through 10 if ( sigma > 9.9 || prevSigma > 9.5 && sigma < prevSigma ) { Flip sign }
	//      (so a singularity, but not noticeable)
	//      5. * ( sin(a * ticks) + 1.05 ) where ticks == frameCount() / tickLength

	// Maybe use relative phase to generate metastable relationships between oscillators?
	// rel phase = ∂w - a sin(rel phase) - 2b sin (2 * rel phase) + sqrt(Q) * zeta
	// where rel phase == relative phase between two interacting components
	// a and b are parameters setting strength of attracting regions in the dynamical landscape
	// sqrt(Q) * zeta == noise term of strength Q
	// ∂w == symmetry breaking term expressing the fact that each element has its own intrinsic behavior

	// But this is more appropriate as a description, not so good for generating behavior
	// But maybe we could still use relative phase?

	// Update: No. All we need to do is model the oscillation of the periods independently
	// (and then later the gains)
	// What we want is a delta function that varies in sigma and skew
	// sigma and skew should covary, so that positive skew is associated with greater variance
	// and negative skew with tighter distribution, to give us the hysteresis we want
	// (i.e., on the downward trend it's more consistent but takes longer)

	// Or maybe period should be stable, and phase resetting is the major intervention?
	// Or period oscillates smoothly, PLUS phase resetting

