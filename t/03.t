#!/usr/bin/env perl6

use v6;

use lib 'lib';

use Test;

BEGIN %*ENV<PERL6_TEST_DIE_ON_FAIL> = 1;

# plan 1;

say 'testing Executer -  Basic'; 
use Net::Jupyter::Executer;

sub fy(*@args) { return @args.join("\n") ~ "\n"};

sub test-result($exec, $v, $o, $e) {
  say 'V->', $exec.value;
  say 'O->',$exec.out;
  say 'E->',$exec.err.gist;
  if $exec.value.starts-with('sub')  {
    ok 'sub' eq $v, "return value { $v.gist } correct";
  }else {
    ok $exec.value  === $v.gist, "return value { $v.gist } correct";
  }
  ok $exec.out    === $o, "output -->" ~ $o ~"<-- correct";
  if $e.defined {
    ok $exec.err.index($e).defined, "correct: { $exec.err }";
  } else {
    ok $exec.err  === Str, "Correct: No error";
  }
}

my @code = [
    [''],
    ['use v6;'
    , 'my $z=3;'
    ],
   [
    'my $y=7+(11/1);'
      , 'my  $x = 4 * 8 + $z;'
      , 'say q/YES/;'
      , 'say $x/1;'
    ],
    [ 'sub xx($d) {', 
      '  return $d*2;',
      '}'      
    ], 
    [  'xx($m)'
    ],
    [
      'say xx(10);'
    ],
    [
      'say 10/0;'
    ],
    [
      'use NO::SUCH::MODULE;'
    ]
];

sub get-exec($i) { my $c=fy(|@code[$i]); say $c;return  Executer.new(:code($c));}

my Executer $exec;
my $t = 0;

lives-ok { test-result(get-exec(0), Any, '', Any) }, "test {++$t} lives";
lives-ok { test-result(get-exec(1), 3, '', Any) }, "test {++$t} lives";
lives-ok { test-result(get-exec(2), True, "YES\n35\n", Any) }, "test {++$t} lives";
lives-ok { test-result(get-exec(3), 'sub', '', Any) }, "test {++$t} lives";
lives-ok { test-result(get-exec(4), Any, '', 'not declared') }, "test {++$t} lives";
lives-ok { test-result(get-exec(5), True, "20\n", Any) }, "test {++$t} lives";
lives-ok { test-result(get-exec(6), Any, '', 'by zero') }, "test {++$t} lives";
lives-ok { test-result(get-exec(7), Any, '', 'find NO::SUCH::MODULE') }, "test {++$t} lives";
lives-ok { get-exec(0).reset }, 'reset' ; 
lives-ok { test-result(get-exec(2), Any, '', 'not declared') }, "test {++$t} lives";

pass "...";

done-testing;
