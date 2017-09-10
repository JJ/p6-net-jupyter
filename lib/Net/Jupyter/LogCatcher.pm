#!/usr/bin/env perl6

unit module Net::Jupyter::LogCatcher;

use v6;
use JSON::Tiny;

use Net::ZMQ::Context:auth('github:gabrielash');
use Net::ZMQ::Socket:auth('github:gabrielash');
use Net::ZMQ::Message:auth('github:gabrielash');

my %PROTOCOL = ('prefix' => -4, 'domain' => -3, 'level' => -2, 'format' => -1
                , 'content' => 1, 'timestamp' => 2, 'target' => 3);

my %LEVELS = ( :critical(0) :error(1) :warning(2) :info(3) :debug(4) :trace(5) );
my %ILVELS = zip(%LEVELS.values, %LEVELS.keys).flat;

my $log-uri := "tcp://127.0.0.1:3999";

class LogCatcher is export {
  has Str $.uri;
  has $.debug is rw = False;

  has Int $!level-max = 3;
  has Str @!domains;
  has Context $!ctx;
  has Socket $!subscriber;
  has Promise $!promise;
  has Str $!prefix;
  has @!zmq-handlers;
  has %!handlers;


  method TWEAK {
    $!uri = $log-uri unless $!uri.defined;
    $!ctx = Context.new:throw-everything;
    %!handlers .= new;
    @!zmq-handlers .= new;
  }

  method DESTROY {
    self.unsubscribe if $!promise.defined;
    $!ctx.shutdown;
  }

  method !default-zmq-handler($content, $timestamp, $level, $domain, $target) {
    say qq:to/MSG_END/;
    ___________________________________________________________________
    $level @ $timestamp (domain: $domain, target: $target)
    $content
    ___________________________________________________________________
    MSG_END
    #:
  }

  method !default-handler(Str $content) {
    say '_______________________________________';
    say $content;
    say '_______________________________________';
  }

  method set-domains-filter(*@l) {
    @!domains = @l;
    return self;
  }

  method set-level-filter(*%h) {
    die "level must be one of { %LEVELS.keys }" unless %h.elems == 1 and  %LEVELS{ %h.keys[0] }:exists;
    $!level-max = %LEVELS{ %h.keys[0] };
    return self;
  }

  method add-zmq-handler( &f:(:$content, :$timestamp, :$level, :$domain, :$target) ) {
      @!zmq-handlers.push(&f);
      return self;
  }

  method add-handler( Str $format,  &f:(Str:D $content) ) {
      %!handlers{$format} = Array[Callable].new unless %!handlers{$format}:exists;
      my @array := %!handlers{$format};
      @array.push(&f);
      return self;
  }

  method !dispatch($msg) {
    my $begin = 0;
    $begin++ while (($begin < $msg.elems) && ($msg[$begin] ne ''));

    if $!debug {
      say "LogCatcher: DISPATCHING THIS:";
      say "$_) ---"  ~ $msg[$_] ~ "---" for ^$msg.elems;
    }

    return if $begin == $msg.elems;
    my $level = $msg[ $begin  + %PROTOCOL<level> ];
    return if %LEVELS{$level} > $!level-max;
    my $domain = $msg[ $begin + %PROTOCOL<domain> ];
    return if @!domains > 0 && ! @!domains.grep( { $_ eq $domain } );

    my $format = $msg[$begin   + %PROTOCOL<format> ];

    given $format {
      when  'zmq' {
        return unless $begin + 3 < $msg.elems;
        my $content =  $msg[ $begin + %PROTOCOL<content> ];
        my $timestamp = $msg[ $begin + %PROTOCOL<timestamp> ];
        my $target  = $msg[ $begin + %PROTOCOL<target> ];

        if @!zmq-handlers.elems > 0 {
          $_(:$content, :$timestamp, :$level, :$domain, :$target)
            for @!zmq-handlers;
        } else {
          self!default-zmq-handler($content, $timestamp, $level, $domain, $target);
        }
      }
      default {
        return unless $begin + 1 < $msg.elems;
        my $content =  $msg[ $begin + %PROTOCOL<content> ];
        if %!handlers{$format}:exists {
          my @handlers = %!handlers{$format};
          $_($content) for @handlers;
        } else {
          self!default-handler($content);
        }
      }
    }
  }#!dispatch

  method subscribe(Str:D $prefix) {
    $!prefix = $prefix;
    $!promise = start {
      #say "LogCatcher: Promise";
      $!subscriber = Socket.new($!ctx, :subscriber, :throw-everything);
      $!subscriber.connect($!uri);
      $!subscriber.subscribe($prefix);
      loop {
          my MsgRecv $m .= new;
          $m.slurp($!subscriber);
          self!dispatch($m);
      }
    }
    return $!promise.defined;
  }

  method unsubscribe(:$async) {
    if ($!promise.defined) {
        $!promise.break;
        CATCH{
          when  X::Promise::Vowed {
            $!subscriber.unsubscribe($!prefix);
            $!subscriber.disconnect.close;
          }
          # this doesn't work, because every exception breaks the promise
          # which means there is effectively no error reporting inside the promise
          # so this has to be redesigned
          default { .throw; }
      }
    }
    #say "LogCatcher: exit Promise";
    $!promise = Promise;
  }


}#LogCatcher
