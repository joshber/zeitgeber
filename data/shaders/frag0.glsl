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

uniform float halfpulse0;
uniform float halfpulse1;
uniform float halfpulse2;

uniform float skew0;
uniform float skew1;
uniform float skew2;

uniform float period0; // in ms
uniform float period1;
uniform float period2;

uniform float phase0; // in ms
uniform float phase1;
uniform float phase2;

uniform float gain0; // 1-based, i.e. a coefficient
uniform float gain1;
uniform float gain2;

uniform float threshold0; // pivot for calculating gain expression, e.g. contrast
uniform float threshold1;
uniform float threshold2;

/*uniform vec3 flare0;
uniform vec3 flare1;
uniform vec3 flare2;
*/

uniform vec3 balance0; // RGB for pulse expression
uniform vec3 balance1;
uniform vec3 balance2;

//
// Distortion uniforms
/*
uniform float dGain;
uniform float dFreq;
uniform float dCenterline;
uniform float dHeading;
uniform float dDecay;
uniform float dStart;
uniform float dEnd;
*/

// pulse phase in [ 0 -.000.. .. 1.0 .999.. .. 0 ]
// -- 0 off-pulse, 1 at center, negative on upslope, positive on downslope
//
// TODO Would it be easier simply to put it in [ 0, 2 ] ?
//
float pulsePhase( float period, float phase, float halfpulse ) {
	float pulse = 2. * halfpulse - 1.;
		// Achtung, make sure this tracks the halfpulse-pulse formula in the controller

	float distanceFromPulseCenter = mod( time, period + pulse ) - phase;
		// + pulse to handle edge-of-period half-pulse problem

	// [ 0 -.000.. .. 1.0 .999.. .. 0 ]
	return	clamp( halfpulse - abs( distanceFromPulseCenter ), 0., halfpulse ) / halfpulse
			* sign( distanceFromPulseCenter );
}

// Easing to simulate Fourier modeling of pulse shape
// - Start with pulse phase in [0,1]
// - Map it to [ sin(-π/2), sin(π/2) ], map that back to [0,1]
// - Map that to [ 1., gain ]
//
// FIXME: ADD SKEW ... SWITCH TO BEZIER EASING? STILL NEED A PHASE THAT COVERS THE WHOLE PULSE
// No, we can do it with a sign. We need a phi that varies according to pulsePhase
// so when skew < 0 π/2 = phi(pulsePhase, skew) < center of pulse
// http://mathforum.org/library/drmath/view/67051.html
//
// Maybe sin( PI * ( abs( phase ) - .5 ) + sign( phase ) (FIXME something something skew) * sin( PI * ( abs( phase ) - .5 ) ) )
// where negative sign( phase ) and positive skew will advance the peak
// No, that's not what we need -- we need to negate the skew but put the phase sign inside the sine somehow
// or maybe we need a version of pulse phase that runs [0,1] inside the sine?
// or maybe it doesn't matter if pulsephase is unsigned?
//
float easing( float phase, float skew, float gain ) {
	float scaledPhase = PI * ( abs( phase ) - .5 );

	float pulse = .5 + .5 * sin( scaledPhase - skew * sin( -sign( phase ) * scaledPhase ) );

	return 1. + pulse * ( gain - 1. );
}

// Right now, pulse expression is just an RGB-weighted contrast enhancement,
// eased according to where in the time course of the pulse we are (pulsePhase)
// TODO -- Add a flare!
//
vec3 pulse( vec3 c, float pulsePhase, float skew, float gain, float threshold, vec3 balance ) {
	return balance.rgb * ( ( c.rgb - threshold ) * easing( pulsePhase, skew, gain ) + threshold );
		// Achtung, color balance here is a MULTIPLIER, not an apportioner
}

// FIXME: Sinusoidal distortion -- DEVELOP
//
vec2 distort( vec2 p ) {
	return p;
	// if ( time > dEnd ) return p;

	//vec2 dp;

/*	float halfpulse = .5 * ( dEnd - dStart );
	float phase = 1. - ( abs( halfpulse - ( time - dStart ) ) / halfpulse );
		// [0,1], 0 at edge of distortion pulse, 1 at peak

	float easing = .5 + .5 * sin( PI * ( phase - .5 ) );


	float freq = 1000. / dFreq;
	dp.s = sin( dHeading ) * ...
	dp.t = cos( dHeading ) * ...
	return p + dp * easing;
*/
	float gainY = .01;
	float freqY = 1000. / 10.;
	float centerlineY = .5;
	float decayY = 2.;
	
	p.s +=	gainY * sin( p.t * time / freqY )
			* pow( p.s < centerlineY ? p.s / centerlineY : ( 1. - p.s ) / ( 1. - centerlineY ), decayY );
				// 1. at the centerline, decays on either side from there

	return p;
}

void main() {
	// We could use vertTexCoord and texOffset (Processing uniforms),
	// but it feels more portable to roll our own

	// Invert y-axis -- Processing y-axis runs top to bottom
	vec2 pos = vec2( gl_FragCoord.s / resolution.s, 1. - (gl_FragCoord.t / resolution.t) );

	// 1-texel offset for convolution filtering
	vec2 off = vec2( 1. / resolution.s, 1. / resolution.t );

	// Add distortion as appropriate
	pos.st = distort( pos );

	// Sample texture data for current fragment
	vec4 c0 = texture2D( stream0, pos );
	vec4 c1 = texture2D( stream1, pos );
	vec4 c2 = texture2D( stream2, pos );

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

	// TODO --
	// Make pulsePhase ± so we can add some asymmetry to the easing -- sharper attack, longer decay etc
	// Maybe have it vary [0,2], with >1 postpeak ...
	// or use a vec2 with sign represented separately

	if ( pulsePhase0 > 0. ) {
		c0.rgb = pulse( c0.rgb, pulsePhase0, skew0, gain0, threshold0, balance0 );
	}
	if ( pulsePhase1 > 0. ) {
		c1.rgb = pulse( c1.rgb, pulsePhase1, skew1, gain1, threshold1, balance1 );
	}
	if ( pulsePhase2 > 0. ) {
		c2.rgb = pulse( c2.rgb, pulsePhase2, skew2, gain2, threshold2, balance2 );
	}

	// TODO: Rethink
	// Blend the textures
	// We use a lighten blend, not a linear tween
	// The video streams are characterized by dark backgrounds with bright shapes
	// So a tween would mute the colors
	vec4 blend = max( c0, max( c1, c2 ) );

	gl_FragColor = vec4( blend.rgb, 1. ) ; //* vertColor;
}
