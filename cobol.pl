#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use IO::Async::Loop;
use IO::Async::Stream;
use Encode;
use utf8;
use open qw/:std :utf8/;

use App::EvalServerAdvanced::Protocol;
use Exporter 'import';

our $VERSION = '0.004';

# ABSTRACT: Example client for App::EvalServerAdvanced


my (@args) = @_;

my $loop = IO::Async::Loop->new();
my $seq = 1;

my $connect_future = $loop->new_future();

$loop->connect(
    addr => {
       family   => "inet",
       socktype => "stream",
       port     => 14401,
       ip       => "192.168.32.1",
    },
    on_stream => sub {
        my $stream = shift;

        $stream->configure(
            on_read => sub {
                my ($self, $bufref, $eof) = @_;

                if ($eof) {
                    print "Disconnected\n";
                    exit(1);
                }

                my ($res, $message, $nbuf) = decode_message($$bufref);
                if ($res) {
                    $$bufref = $nbuf;

                    $|++;
                    if (ref($message) =~ /EvalResponse$/) {
                        print "\n"; # go to a new line
                        my $eseq = $message->sequence;
                        if (!$message->{canceled}) {
                            my $lines = $message->get_contents;
                            print $lines;
                        } else {
                            print "$eseq was canceled\n";
                        }
                    } elsif (ref($message) =~ /Warning$/) {
                        my $eseq = $message->sequence;
                        my $warning = $message->message;
                        print "\nWARN <$eseq> ", $warning, "\n";
                    } else {
                        die "Unhandled message: ". Dumper($message);
                    }
                }

                return 1;
            }
        );

        $loop->add($stream);
        $connect_future->done($stream);
    },
    on_connect_error => sub {die "no connect"}
 );

my $stream = $connect_future->get;

my $lang = "cobol";

my $line = <<"EOF";
000200 IDENTIFICATION DIVISION.
000300 PROGRAM-ID. hello.
000400 PROCEDURE DIVISION.
000500     DISPLAY "Hello, world!".
000600     STOP RUN.

EOF

my $line_utf8 = eval {Encode::decode("utf8", $line)} // $line;  # Term::Readline for me doesn't do the decoding.

my $eval = {
  language => $lang, 
  sequence => $seq, 
  prio => {pr_realtime => {}}, 
  files => [
    {filename => "__code", contents => $line_utf8, encoding => "utf8"}, 
    ],
  encoding => "utf8",  # The encoding I want back, if possible
};

my $message = encode_message(eval => $eval);
$seq++;
$stream->write($message);

$loop->run();
