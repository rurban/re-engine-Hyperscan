package re::engine::Hyperscan;
our ($VERSION, $XS_VERSION);
BEGIN {
  $VERSION = '0.01';
  $XS_VERSION = $VERSION;
  $VERSION = eval $VERSION;
}
use 5.010;
use strict;
use XSLoader ();

# All engines should subclass the core Regexp package
our @ISA = 'Regexp';

BEGIN {
  XSLoader::load;
}

sub import {
  $^H{regcomp} = ENGINE;
}

sub unimport {
  delete $^H{regcomp} if $^H{regcomp} == ENGINE;
}

1;

__END__

=head1 NAME 

re::engine::Hyperscan - Fast Hyperscan regular expression engine - Intel-only

=head1 SYNOPSIS

    use re::engine::Hyperscan;

    if ("Hello, world" =~ /(Hello|Hi), (world)/) {
        print "Greetings, $1!";
    }

=head1 DESCRIPTION

ALPHA - Does not work YET

Replaces perl's regex engine in a given lexical scope with Intel's 
Hyperscan regular expressions provided by -lhs.

This provides the fastest regular expression library on Intel-CPU's
only, but needs to fall back to the core perl regexp compiler with
backtracking, lookbehind, zero-width assertions and more advanced
patterns.  It is typically 50% faster then the core regex engine.

=head1 FUNCTIONS

=over

=item ENGINE

Returns a pointer to the internal Hyperscan engine, the database,
suitable for the XS API C<<< (regexp*)re->engine >>> field.

=back

=head1 AUTHORS

Reini Urban <rurban@cpan.org>

=head1 COPYRIGHT

Copyright 2017 Reini Urban.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
