// FIXME PULSE PHASE AND EASING IS NOT CORRECT


// TODO Develop the wiggle into something controlled by the controller
// Set the envelope in config.json: µ and sd for gain, freq (1000. / f Hz -- pass in f), centerline, decay,
// heading ( mean = π/2, s.d. = π/16 )
// and for duration (Log-normal), and how often they occur (uniform -- so, exponential)
//
// Then start thinking about how distortion could be triggered by visitor activity ...
// maybe certain activity increases the frequency, gain, etc
// Maybe the distortion pulses should come in waves ... ?

// ALSO easy to limit the distortion to a specific stream -- simply alter the fragment position just for that stream
// So these envelopes shoudl be a on a per-oscillator basis ... or maybe a separate set of oscillators?
// Ideally, would oscillator:stream be *:* ?
// Then we'd have two types of oscillators, contrast and distortion
// Each stream could take one of each ...
// Might be too complex to implement just yet

// BUT, I don't think the distortion should be oscillatory
// It should be stochastic, defined by Gaussian envelopes as sketched above
// And possibly event-triggered too
// The controller can specify which streams a particular distortion pulse applies to


// Zeitgeber v0.0001

#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

// _COLOR_ vs _TEXTURE_ depends on whether we're using shader() or filter()
// (d.h., whether there's an underlying pixels[] to which we're applying the filter)
// With TEXTURE you get a builtin sampler called "texture"

#define PROCESSING_COLOR_SHADER
//#define PROCESSING_TEXTURE_SHADER

const float PI = 3.14159265359;

uniform vec2 resolution;
uniform float time; // milliseconds since the start of the draw() loop

// 5/2014: This may look like the Bad Way of doing things but--
// - Processing shader API does not support array binding
// - GLSL ES does not support looping over arrays (in GLSL < 4.0 array indices are const)
//   http://stackoverflow.com/questions/12030711/glsl-array-of-textures-of-differing-size/

//
// Oscillator uniforms

uniform sampler2D stream0;
uniform sampler2D stream1;
uniform sampler2D stream2;

uniform float period0; // in ms
uniform float period1;
uniform float period2;

uniform float phase0; // in ms
uniform float phase1;
uniform float phase2;

uniform float halfpulse0; // in ms
uniform float halfpulse1;
uniform float halfpulse2;

uniform float gain0; // 1-based, i.e. a coefficient
uniform float gain1;
uniform float gain2;

uniform vec3 balance0; // RGB for pulse expression
uniform vec3 balance1;
uniform vec3 balance2;

//
// Distortion uniforms

uniform float dStart;
uniform float dEnd;

uniform float dBalance0;
uniform float dBalance1;
uniform float dBalance2;

uniform float dGain;
uniform float dFreq;
uniform float dDecay;

uniform float dYaxis;
uniform float dHeading;


// pulse phase in [ 0, 1 ] -- 0 off-pulse, 1 at center
float pulsePhase( float period, float phase, float halfpulse ) {
	float relphase = mod( time, period );

	float basecase = abs( relphase - phase );
	float phaseNear0 = abs( phase + ( period - relphase ) );
	float phaseNear1 = abs( relphase + ( period - phase ) );

    float distanceFromPulseCenter = min( min( basecase, phaseNear0 ), phaseNear1 );

	return clamp( halfpulse - distanceFromPulseCenter, 0., halfpulse ) / halfpulse;
}

// Easing to simulate Fourier modeling of pulse shape
// - Start with pulse phase in [ 0, 1 ]
// - Map it to [ sin(-π/2), sin(π/2) ], map that back to [ 0, 1 ]
// - Map that to [ 1., gain ]
//
float easing( float phase, float gain ) {
	float scaledPhase = PI * ( phase - .5 );
	float pulse = .5 + .5 * sin( scaledPhase );

	return 1. + pulse * ( gain - 1. );
}

// Right now, pulse expression is just an RGB-weighted brightness enhancement,
// eased according to where in the time course of the pulse we are (pulsePhase)
//
vec3 pulse( vec3 c, float pulsePhase, float gain, vec3 balance ) {
	return balance.rgb * c.rgb * easing( pulsePhase, gain );
		// Achtung, color balance here is a MULTIPLIER, not an apportioner
}

// Distortion!
// TODO: EASING OVER TIME COURSE, SAME AS WITH OSCILLATOR PULSES
//
vec2 distort( vec2 p ) {
	if ( dEnd <= 0. || dEnd <= dStart ) return p;

	float freq = 1000. / dFreq; // dFreq is in Hz
	
	// FIXME the sin( p.t * time / freq ) is generating a meta-oscillation -- frequency varies over time course
	// it's kind of cool, but not what we wanted initially
	// do we want simply freq ? -- no! produces static distortions
	// time % 1000. / freq ? -- well, that looks cool but it's more of a slow ripple

	float distortionY =
			dGain * sin( p.t * time / freq )
			* pow( p.s < dYaxis ? p.s / dYaxis : ( 1. - p.s ) / ( 1. - dYaxis ), dDecay );
				// 1. at the y-axis, decays on either side from there
				// The branch is to make the decay proportional to the distance
				// from the y-axis to the nearer edge of the texture

	// FIXME: is GLSL pass-by-value for vecN unless you use inout in the parameter prototype?

	vec2 q = p;
	q.s += sin( dHeading ) * distortionY;
	q.t += cos( dHeading ) * distortionY;

	return q;
}

void main() {
	// We could use vertTexCoord and texOffset (Processing uniforms),
	// but it feels more portable to roll our own

	// Invert y-axis -- Processing y-axis runs top to bottom
	vec2 pos = vec2( gl_FragCoord.s / resolution.s, 1. - (gl_FragCoord.t / resolution.t) );

	// 1-texel offset for convolution filtering
	vec2 off = vec2( 1. / resolution.s, 1. / resolution.t );

	// Add distortion as appropriate
	vec2 d = distort( pos );

	//d = pos; //distort( pos );
	vec2 p0 = dBalance0 > 0. ? d : pos;
	vec2 p1 = dBalance1 > 0. ? d : pos;
	vec2 p2 = dBalance2 > 0. ? d : pos;

	// Sample texture data for current fragment
	vec4 c0 = texture2D( stream0, p0 );
	vec4 c1 = texture2D( stream1, p1 );
	vec4 c2 = texture2D( stream2, p2 );

	//
	// For each stream, do something special if its oscillator is on-pulse
	// Right now the something special is just heightened contrast

	// Inspired by http://glsl.heroku.com/e#15220.0

	float pulsePhase0 = pulsePhase( period0, phase0, halfpulse0 );
	float pulsePhase1 = pulsePhase( period1, phase1, halfpulse1 );
	float pulsePhase2 = pulsePhase( period2, phase2, halfpulse2 );

	// TODO --
	// Add a flare, drawing in the color values from neighboring texels
	// Look at http://glsl.heroku.com/e#15220.0 --
	// Maybe use an exponential distance decay from current position

	if ( pulsePhase0 > 0. ) {
		c0.rgb = pulse( c0.rgb, pulsePhase0, gain0, balance0 );
	}
	if ( pulsePhase1 > 0. ) {
		c1.rgb = pulse( c1.rgb, pulsePhase1, gain1, balance1 );
	}
	if ( pulsePhase2 > 0. ) {
		c2.rgb = pulse( c2.rgb, pulsePhase2, gain2, balance2 );
	}

	// TODO: Rethink
	// Blend the textures
	// We use a lighten blend, not a linear tween
	// The video streams are characterized by dark backgrounds with bright shapes
	// So a tween would mute the colors
	vec4 blend = max( c0, max( c1, c2 ) );

	gl_FragColor = vec4( blend.rgb, 1. ) ; //* vertColor;
}
