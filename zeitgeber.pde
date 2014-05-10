// Zeitgeber v0.0001

import java.lang.Math;
import java.util.Random;

import processing.video.*;

// Longer-term TODO --
// Clean up float / int thing in oscillator members

// TOP TODO
// VISUALIZER -- ADD DISTORTION -- less opaque when inactive etc
// Finish distortion -- NOT balanced by stream, uniform across them
//
// THEN: It's time to get to entrainment
//
//
// PLUS, Must decide if period and gain are calibrated to ambient zeitgeber readings
// at startup ... and if so, if there's a way to recalibrate them, i.e., by storing
// original "intrinsic" period and gain ... AND, if so, if the intrinsics can also shift
// over time
// Underlying practical question: If the environment gets quieter than it was originally,
// will the period and gain get lower, or is the configured period/gain a floor?
//
// THEN: Add entrainment etc
//
// PLUS--
// Go up to 8 streams


// Two kinds of zeitgeber, ambient and event (pulse -- i.e., sudden sensor event)

// Period and gain change only in response to ambient zeitgeber, something like Temperature--
// Could be noise in the room or total sensor activity ...
// Period and gain have response curves, something like Perlin's Hermite + Gaussian noise term

// Phase is the only thing that responds to pulse zeitgeber
// Again, a phase response curve -- logistic-type Hermite + Gaussian noise term
//
// Cross-frequency coupling ... something to try for another project


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


boolean showVisualizer;

Random theRNG; // For generating noise terms

PShader shadr;

int nOscillators;
Oscillator[] oscillators;

void setup() {
    size( 1280, 720, P2D );
    //size( displayWidth, displayHeight, P2D );

    colorMode( RGB, 1.0 );
    fill( color( 1., 1., 1., 1. ) ); // In case we * vertColor in the fragment shader
    noStroke();

    showVisualizer = false;

    theRNG = new Random( /* long seed */ );

    loadConfig( true /* load streams */ );
}

void draw() {
    background( color( 0., 0., 0., 1. ) );

    // Every 12 frames, stochastically ...
    if ( theRNG.nextDouble() > .875 ) {
        // Check to see if any oscillators are on the pulse
        for ( int i = 0; i < nOscillators; ++i ) {
            double pulsePhase = oscillators[i].pulsePhase( millis() );
            if ( pulsePhase > 0 ) {
                // TODO See if the other oscillators want to entrain to this one
            }

            // TODO --
            // - Enqueue zeitgeber in the ØMQ pipe
            // - Handle enqueued zeitgeber
        }
    }

    // FIXME: HANDLE DISTORTION

    // Update shader uniforms with texture frame data and oscillator params
    for ( int i = 0; i < nOscillators; ++i ) {
        oscillators[i].setShader(shadr);
    }

    shadr.set( "time", float( millis() ) );
        // Passed as float bc GLSL < 3.0 can't do modulus on ints

    shader(shadr);
    rect( 0, 0, width, height );

    visualizer();
}

//
// Overlays

void visualizer() {
    if ( ! showVisualizer ) return;

    resetShader();
    pushStyle();

    float oscH = 55.;
    float visualizerH = oscH * nOscillators + 30.;

    // Scrim to enhance overlay visibility
    fill( color( 1., 1., 1., .75 ) );
    rect( 0, height - visualizerH, width, height );

    stroke( 1 );

    translate( 0, height - visualizerH );

    for ( int i = 0; i < nOscillators; ++i ) {
        translate( 0, oscH );

        PVector balance = oscillators[i].balance;
        float denom = balance.x + balance.y + balance.z;
        color c = color(    oscillators[i].balance.x / denom, oscillators[i].balance.y / denom,
                            oscillators[i].balance.z / denom, 1. );
        stroke( c );
        fill( c );

        textAlign( RIGHT );
        textSize( 10 );
        text( oscillators[i].name, 90, 1 );

        c = color(  oscillators[i].balance.x / denom, oscillators[i].balance.y / denom,
                    oscillators[i].balance.z / denom, .5 );
        line( 100, 0, width - 100, 0 );

        int period = oscillators[i].period;

        //
        // Mark the pulse region

        float scaledHalfpulse = map( oscillators[i].halfpulse, 0, period, 0, width - 200 );
        float scaledPhaseCenter = map( oscillators[i].phase, 0, period, 0, width - 200 );

        // FIXME: Can we do this without branching logic?
        float scaledStart = scaledPhaseCenter - scaledHalfpulse;
        if ( scaledStart < 0. )
            scaledStart = width - 200 + scaledStart;
        float scaledEnd = ( scaledPhaseCenter + scaledHalfpulse ) % ( width - 200 );

        line( 100 + scaledPhaseCenter, 1., 100 + scaledPhaseCenter, 5. );
        line( 100 + scaledStart, 1., 100 + scaledStart, 3. );
        line( 100 + scaledEnd, 1., 100 + scaledEnd, 3. );

        // Dot contour for the pulse
        for ( int j = 0; j < 5; ++j ) {
            c = color(  oscillators[i].balance.x / denom, oscillators[i].balance.y / denom,
                        oscillators[i].balance.z / denom, 1. -  j * .2 /* fade the dots into the past */ );
            stroke( c );
            fill( c );

            int spacingFactor = 100;
            int t = millis() - j * spacingFactor;

            float phase = (float)( oscillators[i].pulsePhase( t ) );
            float scaledPhase = PI * ( phase - .5 );

            float pulse = -(oscH - 15.) * ( .5 + .5 * sin( scaledPhase ) );

            ellipse( map( t % period, 0, period, 100, width - 100 ), pulse, 3, 3 );
        }
    }

    popStyle();
}

//
// Stream events

void movieEvent( Movie m ) {
    m.read();
}

void stop() { }

//
// Control and delegation

// Fullscreen: For caveats and workarounds
// see http://wiki.processing.org/w/Window_Size_and_Full_Screen
//
boolean sketchFullScreen() {
    return false;
}

void keyPressed() {
    if ( key == 'r' || key == 'R' ) {
        reloadConfig();
    }
    if ( key == 'v' || key == 'V' ) {
        showVisualizer = ! showVisualizer;
    }
}

void reloadConfig() {
    // TODO: Clean up from previous iteration to minimize memory leaks?

    loadConfig( false /* don't load streams */ );
}

void loadConfig( boolean loadStreams ) {
    JSONObject config = loadJSONObject( "config.json" );

    frameRate( config.getFloat( "fps" ) );

    // Shader setup
    shadr = loadShader( "shaders/" + config.getString( "shader" ) + ".glsl" );
    shadr.set( "resolution", float(width), float(height) );

    // Get default oscillator parameters
    // TODO: Can we incorporate this into the loop below for greater regularity, less duplication?
    JSONObject defaultOsc = config.getJSONObject( "default" );
    int halfpulseDef = defaultOsc.getInt( "halfpulse" );
    int periodDef = defaultOsc.getInt( "period" );
    float phaseDef = defaultOsc.getFloat( "phase" );
    float gainDef = defaultOsc.getFloat( "gain" );
    JSONArray blncDef = defaultOsc.getJSONArray( "balance" );
    PVector balanceDef = new PVector( blncDef.getFloat( 0 ), blncDef.getFloat( 1 ), blncDef.getFloat( 2 ) );
    float periodRCHDef = defaultOsc.getFloat( "periodRC_hysteresis" );
    float gainRCHDef = defaultOsc.getFloat( "gainRC_hysteresis" );

    String streamPath = "";
    if ( loadStreams ) {
        streamPath = defaultOsc.getString( "path" );

        // Ensure trailing /
        if ( ! streamPath.equals( "" ) && streamPath.charAt( streamPath.length() - 1 ) != '/' )
            streamPath += "/";
    }

    //
    // Configure the oscillators

    JSONArray oscParams = config.getJSONArray( "oscillators" );

    nOscillators = oscParams.size();
    if ( loadStreams )
        oscillators = new Oscillator[nOscillators];

    for ( int i = 0; i < nOscillators; ++i ) {
        JSONObject osc = oscParams.getJSONObject( i );

        int halfpulse = osc.hasKey( "halfpulse" ) ? osc.getInt( "halfpulse" ) : halfpulseDef;
        int period = osc.hasKey( "period" ) ? osc.getInt( "period" ) : periodDef;
        float phase = osc.hasKey( "phase" ) ? osc.getFloat( "phase" ) : phaseDef;
        float gain = osc.hasKey( "gain" ) ? osc.getFloat( "gain" ) : gainDef;
        PVector balance;
        if ( osc.hasKey( "balance" ) ) {
            JSONArray blnc = osc.getJSONArray( "balance" );
            balance = new PVector( blnc.getFloat( 0 ), blnc.getFloat( 1 ), blnc.getFloat( 2 ) );
        } else {
            balance = balanceDef;
        }
        float periodRCH = osc.hasKey( "periodRC_hysteresis" ) ? osc.getFloat( "periodRC_hysteresis" ) : periodRCHDef;
        float gainRCH = osc.hasKey( "gainRC_hysteresis" ) ? osc.getFloat( "gainRC_hysteresis" ) : gainRCHDef;

        Movie s = null;
        String streamHandle = "";
        if ( loadStreams ) {
            // Start the stream
            streamHandle = osc.getString( "stream" );
            s = new Movie( this, "streams/" + streamPath + streamHandle + ".mov" );
            s.loop();
        }

        // On first call, create new oscillators
        if ( loadStreams ) {
            oscillators[i] = new Oscillator(
                                            i,              // id
                                            streamHandle,   // name
                                            s,              // video stream
                                            halfpulse,
                                            period, 
                                            phase, 
                                            gain,  
                                            balance, 
                                            periodRCH, 
                                            gainRCH
                                );
        } else {
            // A little crude, but I'd rather not muck around with move semantics
            // (i.e., moving Movies to new oscillators)
            oscillators[i].reconfig(
                                    halfpulse, 
                                    period, 
                                    phase, 
                                    gain,
                                    balance, 
                                    periodRCH, 
                                    gainRCH
                            );
        }
    }
}

//
// Oscillator-related

double clamp( double x, double a, double b ) {
    return x < a ? a : x > b ? b : x;
}

double gaussian( double mean, double sd ) {
    // Clamping at 6 sigma should not introduce too much squaring ...
    return mean + sd * clamp( theRNG.nextGaussian(), -6., 6. );
}

// When we need a zero-anchored distribution
// http://en.wikipedia.org/wiki/Log-normal_distribution
//
double lognormal( double mean, double sd ) {
    return Math.exp( gaussian( mean, sd ) );
}

// Perlin's Hermite 6x^5 - 15x^4 + 10x^3
double smootherstep( double a, double b, double x ) {
    // Scale and clamp x to [0,1]
    x = clamp( (x - a) / (b - a), 0., 1. );
    // Evaluate polynomial
    return x * x * x * ( x * ( x * 6. - 15. ) + 10. );
}

class Oscillator {
    int id;
    String name;

    Movie s;

    int halfpulse; // Radius in milliseconds

    int period, phase; // in ms

    float gain; // 1-based, i.e., a coefficient
    PVector balance; // RGB balance for pulse expression

    // Response curve hysteresis terms: > 0 means latency on descending values
    float periodRC_hysteresis, gainRC_hysteresis;

    Oscillator() { }

    Oscillator( int id_, String name_, Movie s_, 
                int halfpulse_,
                int period_, float phase_, 
                float gain_, PVector balance_, 
                float perRCH, float gainRCH
            ) {
        id = id_;
        name = name_;
        s = s_;

        reconfig( halfpulse_, period_, phase_, gain_, balance_, perRCH, gainRCH );
    }

    void reconfig (
                int halfpulse_,
                int period_, float phase_, 
                float gain_, PVector balance_, 
                float perRCH, float gainRCH
            ) {        
        halfpulse = halfpulse_;

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

        //
        // Ints passed as floats bc GLSL < 3.0 can't do modulus on ints

        sh.set( "halfpulse" + id, float(halfpulse) );

        sh.set( "period" + id, float(period) );
        sh.set( "phase" + id, float(phase) );

        sh.set( "gain" + id, gain ); 
        sh.set( "balance" + id, balance );
    }

    // pulse phase in [ 0,1 ] -- 0 off-pulse, 1 at center of pulse
    double pulsePhase( int t ) {
        int relphase = t % period;

        int basecase = abs( relphase - phase );
        int phaseNear0 = abs( phase + ( period - relphase ) );
        int phaseNear1 = abs( relphase + ( period - phase ) );

        int distanceFromPulseCenter = min( min( basecase, phaseNear0 ), phaseNear1 );

        return clamp( (float)( halfpulse - distanceFromPulseCenter ), 0., (float)( halfpulse ) )
                        / (float)( halfpulse );
    }
}

//
// Distortion-related

class Distortion {

}
