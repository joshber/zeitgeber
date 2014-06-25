// PUB-SUB proxy for Zeitgeber
// Josh Berson, 6/2014

// Compile: gcc zeitgeber-proxy.c -lzmq -lczmq

#include <czmq.h>

int main( void ) {
    const char *interface = "*";
    const int fromPUB = 7506;
    const int toSUB = 7507;

    //
    // Bind XSUB and XPUB sockets to *
    // http://czmq.zeromq.org/manual:zsocket

    zctx_t *context = zctx_new();
    assert( context );

    void *xsub = zsocket_new( context, ZMQ_XSUB );
    assert( xsub );
    assert( streq( zsocket_type_str( xsub ), "XSUB" ) );

    void *xpub = zsocket_new( context, ZMQ_XPUB );
    assert( xpub );
    assert( streq( zsocket_type_str( xpub ), "XPUB" ) );

    int rc = zsocket_bind( xsub, "tcp://%s:%d", interface, fromPUB );
    assert( rc = fromPUB );

    rc = zsocket_bind( xpub, "tcp://%s:%d", interface, toSUB );
    assert( rc = toSUB );

    //
    // Set up our proxy
    // http://czmq.zeromq.org/manual:zproxy

    zproxy_t *proxy = zproxy_new( context, xsub, xpub );

    // TODO
    // - Add capture/echoing for debug
    // - Maybe switch to zmq_proxy() if the steerable background proxy proves tricky

    // And ... That's it. The proxy is now running in the background.

    // Wait, so is the above equivalent to zmq_proxy( xsub, xpub, NULL /*capture*? ) ?
    // Bc in the zproxy example, it does not seem to be acting like a while ( 1 ) {}

    // http://lists.zeromq.org/pipermail/zeromq-dev/2014-March/025560.html
    // http://lists.zeromq.org/pipermail/zeromq-dev/2014-March/025565.html

    // Ok, so, per Pieter Hintjens,
    // - CZMQ zproxy reimplements zmq_steerable_proxy so that steerability is abstracted
    //   away from libzmq version (since it's new in libzmq)
    // - Steerable means "maintains a silent PAIR socket which waits for a STOP instruction"

    // This is possible because the zproxy runs in a BACKGROUND thread
    // So we need to avoid calling zproxy_destroy(), since it WILL interrupt that background loop

    //
    // We should never get here
/*
    zproxy_destroy( & proxy );
    zsocket_destroy( context, xsub );
    zsocket_destroy( context, xpub );
    zctx_destroy( & context );

    return 0;
*/
}
