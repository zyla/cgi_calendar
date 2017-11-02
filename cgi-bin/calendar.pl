#!/usr/bin/env perl

use strict;
use DBI;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use MIME::Base64;

my $DATABASE_FILENAME = "db.sqlite3";

my $dbh = DBI->connect("dbi:SQLite:dbname=$DATABASE_FILENAME", undef, undef, {
  AutoCommit => 1,
  RaiseError => 1
});

my $q = CGI->new;

# 0. Basic auth
# 1. Display user's calendar
# 2. Add entry
# 3. Delete entry
# 4. Boss dashboard - status of each employee
# 5. Reserve meeting - given duration, list possible dates

my %entry_type_descriptions = (
  'work' => "Godziny pracy",
  'absence' => "Nieobecność",
  'vacation' => "Urlop",
  'meeting' => "Spotkanie"
);

sub unauthorized {
	print $q->header(
		-status => "401 Unauthorized",
		"WWW-Authenticate" => "Basic realm=\"kalendarz\""
	);
	exit;
}

my %user;

my $authorization = $ENV{HTTP_AUTHORIZATION};
if(!$authorization) {
	unauthorized();
} else {
	$authorization =~ s/Basic //;
	my ($login, $password) = split(':', decode_base64($authorization));
	my $st = $dbh->prepare("SELECT * FROM users WHERE login = ? AND password = ?");
	$st->execute($login, $password);
	if(my $row = $st->fetchrow_hashref) {
		%user = %$row;
	} else {
		unauthorized();
	}
}

sub format_date {
	my $date = shift @_;
	$date =~ s/T/ /;
	return $date;
}

sub page_view_calendar {
	print $q->h1("Kalendarz - $user{full_name}");

	my $st = $dbh->prepare("SELECT * FROM calendar_entries WHERE user_login = ?");
	$st->execute($user{login});

	while(my $row = $st->fetchrow_hashref) {
		print "<div>";
		print $q->p(format_date($row->{date_from}) . " &ndash; " . format_date($row->{date_to}));
		print $q->p($entry_type_descriptions{$row->{entry_type}});
		print "</div>";
	}

	print q(<a href="?page=add_entry">Dodaj nowy wpis</a>);
}

sub page_add_entry {
	print $q->h1("Nowy wpis - $user{full_name}");
}

my $page = $q->param("page");

print $q->header();

my %pages = (
	"view" => sub { page_view_calendar(); },
	"add_entry" => sub { page_add_entry(); }
);

$pages{$page}();
