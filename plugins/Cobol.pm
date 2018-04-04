package Cobol;

use strict;
use warnings;
use Moo::Role;
use Data::Dumper;

sub compile_cobol {
    my( $class, $lang, $code ) = @_;

    open(my $fh, ">cobol.cob") or die "Couldn't open cobol.cob";
    print $fh $code;
    close $fh;

    # TODO look this up from the config file
    %ENV=(%ENV, CPATH=>"/usr/include", C_INCLUDE_PATH=>"/usr/include", COB_CFLAGS=>"-I/langs/gnucobol-2.2/include -I/usr/include", SHELL=>"/bin/bash", PATH=>"/usr/bin/");

    print "---BEGIN COMPILER OUTPUT---\n";
    system("/langs/gnucobol-2.2/bin/cobc", "-W", "-x", "cobol.cob") && die "WTF BBQ $! $?";

    print "---BEGIN PROGRAM OUTPUT---\n";
    exec("/eval/cobol");
}

1;
