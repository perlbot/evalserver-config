package Perlbot;
#package App::EvalServerAdvanced::Sandbox::Plugin::Perlbot;

use strict;
use warnings;
use Moo::Role;

use Data::Dumper;
use B::Deparse;
use Perl::Tidy;
use PerlIO;
use List::Util qw/reduce/;
use Path::Tiny;

do {my $temp; open(my $fh, ">", \$temp); close($fh)};

sub deparse_perl_code {
    my( $class, $lang, $code ) = @_;
    my $sub;
    {
        no strict; no warnings; no charnames;
        $sub = eval "use $]; package botdeparse; sub{ $code\n }; use namespace::autoclean;";
    }
    if( $@ ) { die $@ }

    my %methods = (map {$_ => botdeparse->can($_)} grep {botdeparse->can($_)} keys {%botdeparse::}->%*);

    my $dp = B::Deparse->new("-p", "-q", "-x7", "-d");
    no warnings;
    local *B::Deparse::declare_hints = sub { '' };
    my @out;

    my $clean_out = sub {
        my $ret = shift;
        $ret =~ s/\{//;
        $ret =~ s/package (?:\w+(?:::)?)+;//;
        $ret =~ s/no warnings;//;
        $ret =~ s/\s+/ /g;
        $ret =~ s/\s*\}\s*$//;
        $ret =~ s/no feature ':all';//;
        $ret =~ s/use feature [^;]+;//;
        $ret =~ s/^\(\)//g;
        $ret =~ s/^\s+|\s+$//g;
        return $ret;
    };

    for my $sub (grep {!/^(can|DOES|isa)$/} keys %methods) {
        my $ret = $clean_out->($dp->coderef2text($methods{$sub}));

        push @out, "sub $sub {$ret} ";
    }

    my $ret = $dp->coderef2text($sub);
    $ret = $clean_out->($ret);
    push @out, $ret;

    my $fullout = join(' ', @out);

    my $hide = do {package hiderr; sub print{}; bless {}}; 
    my $tidy_out="";
    eval {
        my $foo = "$fullout";
        Perl::Tidy::perltidy(source => \$foo, destination => \$tidy_out, errorfile => $hide, logfile => $hide);
    };

    $tidy_out = $fullout if ($@);

    print STDOUT $tidy_out;
}

#-----------------------------------------------------------------------------
# Evaluate the actual code
#-----------------------------------------------------------------------------
sub run_perl {
    my( $class, $lang, $code ) = @_;

    $|++;
    my $testfh = select;
    my $outfh = *STDOUT;
    my $errfh = *STDERR;

    my @tells = map {tell $_} $testfh, $outfh, $errfh;

    # TODO fix STDIN to use files

    local $@;
    local @INC = map {s|/home/ryan||r} @INC;
#        local $$=24601;
    close STDIN;
    my @files;
    my $path_stdins = path('stdins')->iterator();
    while (my $filename = $path_stdins->()) {
      push @files, $filename if -f $filename;
    }
    my $randfile = @files[rand()*@files];
    open(STDIN, "<", $randfile);

    local $_;

    my ($ret, $err);
    {
        no strict; no warnings; package main;
        do {
            local $/="\n";
            local $\;
            local $,;
            if ($] >= 5.026) {
                $code = "use $]; use feature qw/postderef refaliasing lexical_subs postderef_qq signatures/; use experimental 'declared_refs';\nuse experimental 'signatures';\n#line 1 \"(IRC)\"\n$code";
            } else {
                $code = "use $]; use feature qw/postderef refaliasing lexical_subs postderef_qq signatures/;\n#line 1 \"(IRC)\"\n$code";
            }
            $ret = eval $code;
            $err = $@;
        }
    }
    select STDOUT;


    my @nextells = map {tell $_} $testfh, $outfh, $errfh;
    my $posout = reduce {$a + $b} map {abs ($nextells[$_] - $tells[$_])} 0..$#tells;


#    print Dumper(\@tells, \@nextells);

    if ($posout == 0) {
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Quotekeys = 0;
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Useqq = 1;
        local $Data::Dumper::Freezer = "dd_freeze";

        no warnings;
        my $out = ref($ret) ? Dumper( $ret ) : "" . $ret;
    
        print $out;
    }

    if( $err ) { print "ERROR: $err" }
}

sub perl_wrap {
    my ($class, $lang, $code) = @_;
    my $qcode = quotemeta $code;

    my @files;
    my $path_stdins = path('stdins')->iterator();
    while (my $filename = $path_stdins->()) {
      push @files, $filename if -f $filename;
    }
    my $randfile = @files[rand()*@files];
    
    my $wrapper = 'use Data::Dumper; 

    $|++;
    use IO::Handle;
    my $testfh = select;
    my $outfh = *STDOUT;
    my $errfh = *STDERR;

    ' . ($lang ne 'perl5.5' ? '
    do {
      local $@;
      eval {
        close(STDIN);
        open(STDIN, "<", \''.$randfile.'\');
      }
    };' : '') . '

    use Fcntl qw/SEEK_CUR/;
    sub systell { sysseek($_[0], 0, SEEK_CUR) }

    my @tells = map {$_->flush(); (tell($_), systell($_))} $testfh, $outfh, $errfh;

    my $val = eval "#line 1 \"(IRC)\"\n'.$qcode.'";

    my @nextells = map {$_->flush(); (tell($_), systell($_))} $testfh, $outfh, $errfh;

    if ($@) {
      print "ERROR: $@";
    } else {
      use List::Util qw/reduce/; 
      my $posout = reduce {$a + $b} map {abs ($nextells[$_] - $tells[$_])} 0..$#tells;

      if ($posout == 0) {
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Quotekeys = 0;
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Useqq = 1;
        $val = ref($val) ? Dumper ($val) : "".$val;
#        $val = " $val" if ($[ < 5.008); # fuck 5.6
        print $val;
      } 
    }
    ';
    return $wrapper;
}

1;
