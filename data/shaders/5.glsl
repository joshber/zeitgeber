// TODO
//
// Generate shader source from template at setup() based on nOscillators ?
//
// Start thinking about how distortion could be triggered by visitor activity ...
// maybe certain activity increases the frequency, gain, etc
// Maybe the distortion pulses should come in waves ... ?

// Should distortion envelopes be a on a per-oscillator basis ... or maybe a separate set of oscillators?
// Ideally, would oscillator:stream be *:* ?
// Then we'd have two types of oscillators, contrast and distortion
// Each stream could take one of each ...
// Might be too complex to implement just yet

// ANOTHER Thought --
// Keep oscillator:stream 1:1 for this iteration (i.e., Khoj and ISEA 2015)
// Keep distortion non-oscillatory -- it's going to be keyed (stochastically) to ambient noise
// BUT, create TWO KINDS of oscillator pulse functions
// Brightness enhancement is one
// Blur is the other
// Pass in per-oscillator flags indicating which to use
// The problem would be, it's difficult to implement decent dynamic range with blur
// GLSL Mats are limited to 5x5, so sampling beyond a radius of 2 would be expensive
// -- either you use arrays, or you could use a pair of vec4s (say, blurring only in the x dimension)
// Would saturation really be more noticeable than with brightness enhancement?
// Maybe two vec4s would work nicely. Saturation would mean "weight at uv ± 4px == weight at uv"
// So you define a "decay from origin" power fn that is noticeable at gain = 2 and saturates at gain ≈ 20?


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
uniform sampler2D stream3;
uniform sampler2D stream4;

uniform float period0; // in ms
uniform float period1;
uniform float period2;
uniform float period3;
uniform float period4;

uniform float phase0; // in ms
uniform float phase1;
uniform float phase2;
uniform float phase3;
uniform float phase4;

uniform float halfpulse0; // in ms
uniform float halfpulse1;
uniform float halfpulse2;
uniform float halfpulse3;
uniform float halfpulse4;

uniform float gain0; // 1-based, i.e. a coefficient
uniform float gain1;
uniform float gain2;
uniform float gain3;
uniform float gain4;

uniform vec3 balance0; // RGB for pulse expression
uniform vec3 balance1;
uniform vec3 balance2;
uniform vec3 balance3;
uniform vec3 balance4;


//
// Distortion uniforms

uniform float dStart;
uniform float dEnd;

uniform float dBalance0;
uniform float dBalance1;
uniform float dBalance2;
uniform float dBalance3;
uniform float dBalance4;

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
vec2 distort( vec2 p ) {
	if ( dEnd <= 0. || dEnd <= dStart ) return p;

	float freq = 1000. / dFreq; // dFreq is in Hz
/*
	// Experiment in making the axis of perturbance orthongonal to the axis of the overall distortion
	// The following is not really correct ... but probably not worth pursuing

	float orthogonal = dHeading - .5 * PI;
	float axis0 = dYaxis * cos( dHeading );// + dYaxis * cos( dHeading );
	float axis = p.s * sin( orthogonal ) + p.s * cos( orthogonal );

	float distortion =
			dGain * sin( axis * time / freq )
			* pow( axis < axis0 ? axis / axis0 : ( 1. - axis ) / ( 1. - axis0 ), dDecay );
*/
	float distortion =
			dGain * sin( p.t * time / freq )
			* pow( p.s < dYaxis ? p.s / dYaxis : ( 1. - p.s ) / ( 1. - dYaxis ), dDecay );
				// 1. at the y-axis, decays on either side from there
				// The branch is to make the decay proportional to the distance
				// from the y-axis to the nearer edge of the texture

	// Ease in and out
	float midpoint = dStart + .5 * ( dEnd - dStart );
	float phase = ( midpoint - time ) / ( midpoint - dStart );
	float easing = .5 + .5 * sin( PI * ( phase - .5 ) );

	//
	// Note we're using x-dimension perturbance for both dimensions here
	// If we use a distortionX for q.t it doesn't look as good
	// -- you get two orthogonal bands of perturbance, not a unified effect

	vec2 q = p;
	q.s += sin( dHeading ) * distortion * easing;
	q.t += cos( dHeading ) * distortion * easing;

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

	// Apply distortion
	vec2 p0 = d * dBalance0 + pos * ( 1. - dBalance0 );
	vec2 p1 = d * dBalance1 + pos * ( 1. - dBalance1 );
	vec2 p2 = d * dBalance2 + pos * ( 1. - dBalance2 );
	vec2 p3 = d * dBalance3 + pos * ( 1. - dBalance3 );
	vec2 p4 = d * dBalance4 + pos * ( 1. - dBalance4 );

	// Sample texture data for current fragment
	vec4 c0 = texture2D( stream0, p0 );
	vec4 c1 = texture2D( stream1, p1 );
	vec4 c2 = texture2D( stream2, p2 );
	vec4 c3 = texture2D( stream3, p3 );
	vec4 c4 = texture2D( stream4, p4 );

	//
	// For each stream, do something special if its oscillator is on-pulse
	// Right now the something special is just color-balanced brightness enhancement

	float pulsePhase0 = pulsePhase( period0, phase0, halfpulse0 );
	float pulsePhase1 = pulsePhase( period1, phase1, halfpulse1 );
	float pulsePhase2 = pulsePhase( period2, phase2, halfpulse2 );
	float pulsePhase3 = pulsePhase( period3, phase3, halfpulse3 );
	float pulsePhase4 = pulsePhase( period4, phase4, halfpulse4 );

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
	if ( pulsePhase3 > 0. ) {
		c3.rgb = pulse( c3.rgb, pulsePhase3, gain3, balance3 );
	}
	if ( pulsePhase4 > 0. ) {
		c4.rgb = pulse( c4.rgb, pulsePhase4, gain4, balance4 );
	}

	//
	// Blend the textures
	// We use a lighten blend, not a linear tween
	// The video streams are characterized by dark backgrounds with bright shapes
	// So a tween would mute the colors

	vec4 blend = max( c0, max( c1, max( c2, max( c3, c4 ) ) ) );

	gl_FragColor = vec4( blend.rgb, 1. ) ; //* vertColor;
}
