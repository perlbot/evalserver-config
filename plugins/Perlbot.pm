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

my $AcmeCode = << 'EOF';
package Acme::RandomOS;
  use File::Temp;
  BEGIN {
    $Acme::RandomOS::__original="".$^O;
  }
  sub TIESCALAR {
    my $a; $a=\$a;
    return bless $a, __PACKAGE__;
  }
  sub FETCH {
    my ($p)=caller(1); 
    if ($p eq 'File::Temp' || $p =~ /^Inline/) {
      return $Acme::RandomOS::__original
    } else {
#      my @os=qw/aix bsdos dynixptx darwin freebsd haiku linux hpux irix next openbsd dec_osf svr4 sco_sv unicos unicosmk solaris sunos MSWin32 dos os2 cygwin VMS vos os390 os400 posix-bc riscos amigaos macos 3b1 atari MSWinCE xenix MSWin16 MSWin63 WSL minix vxworks ecos cpm pdp-11/; 
      my @os = qw/VMS/;
      $os[rand()*@os];
    } 
  };
  {my$hidden;tie$hidden,'Acme::RandomOS';$^O=$hidden};
EOF

my $ZathrasCode = <<'EOF';
# This started out as a bad babylon 5 joke, now it's a weird 
# meta class that captures all method calls and arguments
# Slightly used to 
do {
    package
    Zathras;
    our $AUTOLOAD;
    use overload '""' => sub { ## no critic
        my $data = @{$_[0]{args}}? qq{$_[0]{data}(}.join(', ', map {"".$_} @{$_[0]{args}}).qq{)} : qq{$_[0]{data}};
        my $old = $_[0]{old};

        my ($pack, undef, undef, $meth) = caller(1);

        if ($pack eq 'Zathras' && $meth ne 'Zahtras::dd_freeze') {
            if (ref($old) ne 'Zathras') {
                return "Zathras->$data";
            } else {
                return "${old}->$data";
            }
        } else {
           $old = "" if (!ref($old));
           return "$old->$data"
        }
      };
    sub AUTOLOAD {$AUTOLOAD=~s/.*:://; bless {data=>$AUTOLOAD, args => \@_, old => shift}}
    sub DESTROY {}; # keep it from recursing on destruction
    sub dd_freeze {$_[0]=\($_[0]."")}
    sub can {my ($self, $meth) = @_; return sub{$self->$meth(@_)}}
    };
EOF

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
{ local $@;
eval $AcmeCode;
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

sub get_stdin {
    my @std_files;
    my $path_stdins = path('stdins')->iterator();
    while (my $filename = $path_stdins->()) {
      push @std_files, $filename if -f $filename;
    }
    
    my $randfile = @std_files[rand()*@std_files];
    return $randfile
}

sub perl_wrap_file {
    my ($class, $lang, $incode) = @_;

    my $code = "";
    my $codefile = Path::Tiny->tempfile(TEMPLATE => "perl_code_XXXXXXXXXX", DIR => '/eval/', UNLINK => 0);

    my ($version) = ($lang =~ /^perl5\.([.0-9]*)t?$/);

    if ($lang eq 'perl' || $lang eq 'perlt') {
        # TODO this should be more dynamic
        $code = "use v5.31; no strict; use feature qw/isa postderef refaliasing lexical_subs postderef_qq signatures/; use experimental 'declared_refs';\nuse experimental 'isa';\nuse experimental 'signatures';\n#line 1 \"(IRC)\"\n$incode";
    } elsif ($version >= 8) {
      $code = qq{use v5.$version;\nno strict;no warnings;\n};
      if ($version >= 22) {
        $code .= q{BEGIN{require strict; $^H &= ~strict->all_explicit_bits;};};
      } elsif ($version > 16) {
        $code .= q(BEGIN {$^H &= ~0xe0;};);
      }
      $code .= qq{\n#line 1 "(IRC)"\n$incode};

    } else {
      $code = $incode;
    }

    $codefile->spew_utf8($code);

    my $randfile = get_stdin();

    my $wrapper = q[use Data::Dumper; 
    use strict;
    $|++;
    use IO::Handle;
    my $testfh = select;
    my $outfh = *STDOUT;
    my $errfh = *STDERR;
    {local $@;
    eval {
    binmode($outfh, ":encoding(UTF-8)");
    binmode($errfh, ":encoding(UTF-8)");
    };
    };
    my $randfile = '].$randfile.q[';

    local $/="\n";
    local $\;
    local $,;

    my $AcmeCode= <<'EOF';
].$AcmeCode.q[
EOF

my $ZathrasCode= <<'EOF';
].$ZathrasCode.q[
EOF

    
  { local $@;
#    eval $AcmeCode;
  }
  { local $@;
    eval $ZathrasCode;
  }

    eval {
      local $@;
      close(STDIN);
      open(STDIN, "<", $randfile);
    };

    use Fcntl qw/SEEK_CUR/;
    sub systell { sysseek($_[0], 0, SEEK_CUR) }

    my @tells = map {$_->flush(); (tell($_), systell($_))} $testfh, $outfh;

    my $value = do ']. $codefile .q[';
    my $err=$@;

    my @nextells = map {$_->flush(); (tell($_), systell($_))} $testfh, $outfh;
    ].($lang =~ /5\.6/? 'print $value' : q[
    if ($err) {
      print "ERROR: $err";
    } else {
      use List::Util qw/reduce/; 
      my $posout = reduce {$a + $b} map {abs ($nextells[$_] - $tells[$_])} 0..$#tells;

      if ($posout == 0) {
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Quotekeys = 0;
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Useqq = 1;
        local $Data::Dumper::Freezer = "dd_freeze";
        $value = ref($value) ? Dumper ($value) : "".$value;
        print $value;
      } 
    }
    ]);
    return $wrapper;
}

1;
