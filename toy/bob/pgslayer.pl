#!/usr/bin/env perl

use strict; use warnings;

use AnyEvent;
use AnyEvent::HTTPD;
use AnyEvent::DBI;

use Encode;
use Scalar::Util qw(blessed);

sub pp {
  my $v = shift;
  return qq(nil)  if !defined($v);
  return encode_utf8(blessed($v).":".qq("$v")) if blessed($v);
  return encode_utf8(qq("$v")) if !ref($v);
  return '[ '.join(', ', map { pp($_) } @{$v}).' ]'
    if UNIVERSAL::isa($v,'ARRAY');
  return '{ '.join(', ', map { pp($_).q(: ).pp($v->{$_}) } sort keys %{$v}).' }'
    if UNIVERSAL::isa($v,'HASH');
  return encode_utf8(qq("???:$v"));
}

use JSON;
use URI;

sub config {
  my ($name) = @_;
  $name or die "$0 <configfile>";
  open(my $fh, '<:utf8', $name) or die $!;
  local $/;
  my $json = <$fh>;
  close($fh);
  return decode_json($json);
}

my $_db = {};

sub run {
  my $config = config(@_);

  my $httpd = AnyEvent::HTTPD->new (
    host => $config->{httpd_host},
    port => $config->{httpd_port},
  );

  my $db = sub {
    my ($name) = @_;
    my $conf = $config->{db}->{$name} or return;
    return $_db->{$name} ||=
      AnyEvent::DBI->new (
        $conf->{location},
        $conf->{username},
        $conf->{password},
      );
  };

  $httpd->reg_cb(
    '' => sub {
      my ($httpd,$req) = @_;

      print STDERR join(', ',
        'method=' => $req->method,
        'URL='    => pp($req->url),
        'vars='   => pp({$req->vars}),
        'headers='=> pp($req->headers),
        'body='   => pp($req->content),
      );

      my $error = sub {
        $req->respond([@_]);
        $httpd->stop_request;
        return;
      };

      my $url = URI->new($req->url);
      my $path = $url->path;

      print STDERR "path $path, content ".$req->content."\n";

      my ($db_name) = ($path =~ m{^/(\w+)$}) or return $error->(404);

      my $json = eval { decode_json($req->content) };
      !$@ && ref($json) eq 'HASH' or return $error->(418,$@);

      my $sql = $json->{sql} or return $error->(501);
      my $params = $json->{params} || [];

      my $dbh = $db->($db_name) or return $error->(404);

      $dbh->exec($sql,@$params,sub {
        my ($dbh,$rows,$rv) = @_;

        my $response = {};
        $response->{status} = $rv   if $rv;
        $response->{error}  = $dbh->errstr;
        $response->{rows}   = $rows if $rows;

        $req->respond([200,'OK',{ 'Content-Type' => 'text/json' }, encode_json($response)]);
      });
    },
  );

  $httpd->run;
}

run(@ARGV);