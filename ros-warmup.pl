#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use LWP::UserAgent;
use HTTP::Request;
use URI::Escape qw(uri_escape);
use POSIX qw(strftime);
use Sys::Syslog qw(openlog syslog closelog);

# --- настройки ---
my $BASE        = $ENV{WARMUP_BASE}    // 'http://localhost';
my $CACHE_FILE  = $ENV{WARMUP_CACHE_FILE}   // "ros7.version.cache";
my $KEEP        = $ENV{WARMUP_KEEP}    // 3;      # сколько свежих версий на файл
my $TIMEOUT     = $ENV{WARMUP_TIMEOUT} // 5;      # сек, на один запрос
my $VERBOSE     = $ENV{WARMUP_VERBOSE} // 0;

my $CACHE_URL   = "$BASE/routeros/$CACHE_FILE";
openlog('ros-warmup', 'pid', 'daemon');

# --- http-клиент ---
my $ua = LWP::UserAgent->new(
    timeout       => $TIMEOUT,
    agent         => 'ros-warmup/1.0',
    ssl_opts      => {
        verify_hostname => 0,   # localhost, самоподписанный
        SSL_verify_mode => 0,
    },
);
$ua->env_proxy;

sub log_msg { my ($msg) = @_; print "$msg\n" if $VERBOSE; syslog('info', '%s', $msg); }

sub fetch_url {
    my ($url) = @_;
    my $res = $ua->get($url);
    unless ($res->is_success) {
        log_msg("FAIL  $url -> " . $res->status_line);
        return undef;
    }
    return $res->decoded_content;
}

# --- 1. тянем кэш ---
my $cache_body = fetch_url($CACHE_URL);
unless (defined $cache_body) {
    log_msg("Не удалось получить кэш $CACHE_URL — выходим");
    exit 1;
}

# --- 2. парсим ---
# Формат строки: <file>_<version>=<value>|<timestamp>
my %by_file;   # file => { version => 1 }

for my $line (split /\r?\n/, $cache_body) {
    next if $line eq '';
    my ($key, $rest) = split /=/, $line, 2;
    next unless defined $rest;
    $key =~ s/^\s+|\s+$//g;

    # file — это всё до последнего '_'
    my ($file, $version) = $key =~ /^(.+)_(\d+(?:\.\d+)*)$/;
    next unless defined $file && defined $version;

    $by_file{$file}{$version} = 1;
}

unless (%by_file) {
    log_msg("Кэш пуст или не содержит подходящих ключей — выходим");
    exit 0;
}

# --- 3. для каждого файла — KEEP свежих версий ---
sub version_cmp {
    my @a = split /\./, $a;
    my @b = split /\./, $b;
    my $n = @a > @b ? @a : @b;
    for my $i (0 .. $n - 1) {
        my $x = $a[$i] // 0;
        my $y = $b[$i] // 0;
        return $x <=> $y if $x != $y;
    }
    return 0;
}

my $total = 0;
my $ok    = 0;

for my $file (sort keys %by_file) {
    my @versions = sort { version_cmp($b, $a) } keys %{ $by_file{$file} };
    my @top = @versions[0 .. ($KEEP - 1 < $#versions ? $KEEP - 1 : $#versions)];

    for my $v (@top) {
        $total++;
        my $url = sprintf('%s/routeros/%s?version=%s',
            $BASE,
            uri_escape($file),
            uri_escape($v),
        );

        my $body = fetch_url($url);
        if (defined $body) {
            chomp $body;
            log_msg("OK    $file $v -> $body");
            $ok++;
        }
    }
}

log_msg("Готово: $ok/$total успешных прогревов");

exit($ok == $total ? 0 : 1);
