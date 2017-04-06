# NAME 

re::engine::Hyperscan - Fast Hyperscan regular expression engine - Intel-only

# SYNOPSIS

    use re::engine::Hyperscan;

    if ("Hello, world" =~ /(Hello|Hi), (world)/) {
        print "Greetings, $1!";
    }

# DESCRIPTION

ALPHA - Does not work YET

Replaces perl's regex engine in a given lexical scope with Intel's 
Hyperscan regular expressions provided by -lhs.

This provides the fastest regular expression library on Intel-CPU's
only, but needs to fall back to the core perl regexp compiler with
backtracking, zero-width assertions and more advanced patterns.  It is
typically 50% faster then the core regex engine.

# FUNCTIONS

- ENGINE

    Returns a pointer to the internal Hyperscan engine, the database,
    suitable for the XS API `(regexp*)re->engine` field.

# AUTHORS

Reini Urban <rurban@cpan.org>

# COPYRIGHT

Copyright 2017 Reini Urban.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
