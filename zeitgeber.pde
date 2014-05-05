// Zeitgeber v0.0001

import java.util.Random;

import processing.video.*;

// Longer-term TODO --
// Clean up float / int thing in oscillator members

// ****** TODO --
// Finish parameterizing pulse diameter, pulse skew, and gain threshold
// changes in loadConfig, setShader, and in the shader itself
//
// That way, with ease in / ease out, you could have a single oscillator model
// that worked both as a pulse and a sine
// D.h., when pulse diamter == period, it's a sine
//
//
// PLUS, Must decide if period and gain are calibrated to ambient zeitgeber readings
// at startup ... and if so, if there's a way to recalibrate them, i.e., by storing
// original "intrinsic" period and gain ... AND, if so, if the intrinsics can also shift
// over time
// Underlying practical question: If the environment gets quieter than it was originally,
// will the period and gain get lower, or is the configured period/gain a floor?
//
// PLUS--
// Go up to 7 streams


// Two kinds of zeitgeber, ambient and event (pulse -- i.e., sudden sensor event)

// Period and gain change only in response to ambient zeitgeber, something like Temperature--
// Could be noise in the room or total sensor activity ...
// Period and gain have response curves, something like Perlin's Hermite + Gaussian noise term

// Phase is the only thing that responds to pulse zeitgeber
// Again, a phase response curve -- logistic-type Hermite + Gaussian noise term


// Ok, from the latest notes (19.4.14)--

// millis() % 41 (pulsewidth) check to see if any oscillators are on the pulse
// If so, they broadcast to others, which may entrain according to a phase response curve
// Maximum phase response should be at antiphase from the on-pulse oscillator (cf Czeisler and Gooley 2007)
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

int halfpulse;
int pulse;
// In milliseconds. Actual half-pulse is .5 less
// To see if an oscillator is on pulse we test
// abs( millis() % ( period + pulse ) - phase ) < halfpulse
// if == 0 we're exactly at the center of the pulse
// otherwise need a half-pulse radius around that exact center
// TODO: Would it be more intuitive to use <= halfpulse and have pulse be 2*halfpulse + 1?

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
    background( color(0., 0., 0.) );

    // Every 12 frames, stochastically ...
    if ( theRNG.nextDouble() > .875 ) {
        // Check to see if any oscillators are on the pulse
        for ( int i = 0; i < nOscillators; ++i ) {
            double pulsePhase = oscillators[i].pulsePhase();
            if ( pulsePhase > 0 ) {
                // TODO See if the other oscillators want to entrain to this one
            }

            // TODO --
            // - Perturb period, phase, gain, threshold, and pulse diameter with noise ?
            // - Enqueue zeitgeber in the ØMQ pipe
            // - Handle enqueued zeitgeber
        }
    }

    // Update shader uniforms with texture frame data and oscillator params
    for ( int i = 0; i < nOscillators; ++i ) {
        oscillators[i].setShader(shadr);
    }

    shadr.set( "time", float( millis() ) );
    // Passed as float bc GLSL < 3.0 can't do modulus on ints

    shader(shadr);
    fill( color(1., 1., 1.) ); // gives us the option of * vertColor in frag shader
    rect( 0, 0, width, height );
}

// Movie events
void movieEvent( Movie m ) {
    m.read();
}
void stop() { }

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

    // Shader setup
    shadr = loadShader( "shaders/" + config.getString( "shader" ) + ".glsl" );
    shadr.set( "resolution", float(width), float(height) );

    // Get default oscillator parameters
    // TODO: Can we incorporate this into the loop below for greater regularity, less duplication?
    JSONObject defaultOsc = config.getJSONObject( "default" );
    int pulseRadiusDef = defaultOsc.getInt( "pulseRadius" );
    float pulseSkewDef = defaultOsc.getFloat( "pulseSkew" );
    int periodDef = defaultOsc.getInt( "period" );
    float phaseDef = defaultOsc.getFloat( "phase" );
    float gainDef = defaultOsc.getFloat( "gain" );
    float gainThresholdDef = defaultOsc.getFloat( "gainThreshold" );
    JSONArray blncDef = defaultOsc.getJSONArray( "balance" );
    PVector balanceDef = new PVector( blncDef.getFloat( 0 ), blncDef.getFloat( 1 ), blncDef.getFloat( 2 ) );
    float periodRCHDef = defaultOsc.getFloat( "periodRC_hysteresis" );
    float gainRCHDef = defaultOsc.getFloat( "gainRC_hysteresis" );

    // TODO --
    // Parameterize pulse radius and gain threshold per-oscillator

    halfpulse = pulseRadiusDef;
    pulse = halfpulse * 2 - 1;

    // THIS WILL CHANGE SHORTLY
    gainThreshold = gainThresholdDef;

    // At the moment, pulse diameter is fixed -- But could be made mutable
    // Passed as floats bc GLSL < 3.0 can't do mixed float-int arithmetic
    shadr.set( "halfpulse", float(halfpulse) );
    shadr.set( "pulse", float(pulse) );

    shadr.set( "threshold", gainThreshold );

    //
    // Configure the oscillators

    JSONArray oscParams = config.getJSONArray( "oscillators" );

    nOscillators = oscParams.size();
    oscillators = new Oscillator[nOscillators];

    for ( int i = 0; i < nOscillators; ++i ) {
        JSONObject osc = oscParams.getJSONObject( i );

        int pulseRadius = osc.hasKey( "pulseRadius" ) ? osc.getInt( "pulseRadius" ) : pulseRadiusDef;
        float pulseSkew = osc.hasKey( "pulseSkew" ) ? osc.getFloat( "pulseSkew" ) : pulseSkewDef;
        int period = osc.hasKey( "period" ) ? osc.getInt( "period" ) : periodDef;
        float phase = osc.hasKey( "phase" ) ? osc.getFloat( "phase" ) : phaseDef;
        float gain = osc.hasKey( "gain" ) ? osc.getFloat( "gain" ) : gainDef;
        float gainThreshold = osc.hasKey( "gainThreshold" ) ? osc.getFloat( "gainThreshold" ) : gainThresholdDef;
        PVector balance;
        if ( osc.hasKey( "balance" ) ) {
            JSONArray blnc = osc.getJSONArray( "balance" );
            balance = new PVector( blnc.getFloat( 0 ), blnc.getFloat( 1 ), blnc.getFloat( 2 ) );
        } else {
            balance = balanceDef;
        }
        float periodRCH = osc.hasKey( "periodRC_hysteresis" ) ? osc.getFloat( "periodRC_hysteresis" ) : periodRCHDef;
        float gainRCH = osc.hasKey( "gainRC_hysteresis" ) ? osc.getFloat( "gainRC_hysteresis" ) : gainRCHDef;

        // Start the stream
        String streamHandle = osc.getString( "stream" );
        Movie s = new Movie( this, "streams/" + streamHandle + ".mov" );
        s.loop();

        oscillators[i] = new Oscillator(
                                        i,          // id
                                        s,          // video stream
                                        pulseRadius, 
                                        pulseSkew, 
                                        period, 
                                        phase, 
                                        gain, 
                                        gainThreshold, 
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

    int halfpulse, pulse; // widths in ms
    float pulseSkew;

    int period, phase; // in ms

    float gain; // 1-based, i.e., a coefficient
    float gainThreshold;
    PVector balance; // RGB for pulse expression

    // Response curve hysteresis terms: > 0 means latency on descending values
    float periodRC_hysteresis, gainRC_hysteresis;

    Oscillator() { }

    Oscillator( int id_, Movie s_, 
                int pulseR_, float pulseS_, 
                int period_, float phase_, 
                float gain_, float gainT_, PVector balance_, 
                float perRCH, float gainRCH
            ) {
        id = id_;
        s = s_;

        halfpulse = pulseR_;
        pulse = 2 * halfpulse - 1;
        pulseSkew = pulseS_;

        period = period_;
        phase = int( phase_ * period ); // Map phase to period

        gain = gain_;
        gainThreshold = gainT_;
        balance = balance_;

        periodRC_hysteresis = perRCH;
        gainRC_hysteresis = gainRCH;
    }

    void setShader( PShader sh ) {
        PImage frame = s;
        sh.set( "stream" + id, frame );

        //
        // Ints passed as floats bc GLSL < 3.0 can't do modulus on ints

        //sh.set( "halfpulse" + id, float(halfpulse) );
        //sh.set( "pulse" + id, float(pulse) );
        //sh.set( "skew" + id, pulseSkew );

        sh.set( "period" + id, float(period) );
        sh.set( "phase" + id, float(phase) );

        sh.set( "gain" + id, gain );
        //sh.set( "threshold" + id, gainThreshold );
        sh.set( "balance" + id, balance );
    }

    // pulse phase in [0,1] -- 0 off-pulse, 1 at center of pulse
    double pulsePhase() {
        return clamp( float( halfpulse - abs( millis() % ( period + pulse ) - phase ) ), 0., float(halfpulse) )
                / float(halfpulse);
            // period + pulse to handle edge-of-period half-pulse problem
    }
}
