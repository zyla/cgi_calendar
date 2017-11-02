#!/usr/bin/env perl

use strict;
use utf8;
use DBI;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use MIME::Base64;
use POSIX qw(strftime mktime);

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

# userdate - string, "YYYY-MM-DD hh:mm"
# timestamp - seconds since Unix epoch

# Parse userdate.
# Returns undef on failure.
sub userdate_to_timestamp {
	my $date = shift @_;
	if($date =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/) {
		return mktime(0, $4, $3, $2, $1, $0);
	} else {
		return undef;
	}
}

sub timestamp_to_userdate {
	my $time = shift @_;
	return strftime("%F %R", localtime($time));
}

sub page_view_calendar {
	print $q->header("text/html; charset=utf-8");

	print $q->h1("Kalendarz - $user{full_name}");

	my $st = $dbh->prepare("SELECT * FROM calendar_entries WHERE user_login = ?");
	$st->execute($user{login});

	while(my $row = $st->fetchrow_hashref) {
		print "<div>";
		print $q->p($row->{date_from} . " &ndash; " . $row->{date_to});
		print $q->p($entry_type_descriptions{$row->{entry_type}});
		print "</div>";
	}

	print q(<a href="?page=add_entry">Dodaj nowy wpis</a>);
}

sub parse_add_entry_request {
	my $errors = shift @_;

	my $entry_type = $q->param('entry_type');
	unless($entry_type && grep { $_ == $entry_type } (keys %entry_type_descriptions)) {
		push @$errors, "Nieprawidłowy typ";
	}

	my $date_from = $q->param('date_from');
	my $date_to_ts;
	unless(my $date_from_ts = userdate_to_timestamp($date_from)) {
		push @$errors, "Nieprawidłowa data rozpoczęcia";
	}

	my $date_to = $q->param('date_to');
	my $date_from_ts;
	unless($date_to_ts = userdate_to_timestamp($date_to)) {
		push @$errors, "Nieprawidłowa data zakończenia";
	}

	if($date_from_ts && $date_to_ts && $date_to_ts le $date_from_ts) {
		push @$errors, "Data zakończenia powinna być późniejsza niż data zakończenia";
	}

	if(@$errors) {
		return undef;
	} else {
		return (
			"entry_type" => $entry_type,
			"date_from" => $date_from,
			"date_to" => $date_to
		);
	}
}

sub save_entry {
	my $entry = shift @_;
	my $st = $dbh->prepare("INSERT INTO calendar_entries(user_login, entry_type, date_from, date_to) VALUES (?, ?, ?, ?)");
	$st->execute(
		$entry->{user_login},
		$entry->{entry_type},
		$entry->{date_from},
		$entry->{date_to});
}

sub page_add_entry {
	my @errors = ();

	if($ENV{REQUEST_METHOD} eq "POST") {
		my %record = parse_add_entry_request(\@errors);
		if(!@errors) {
			$record{user_login} = $user{login};
			save_entry(\%record, \@errors);
			if(!@errors) {
				print $q->redirect("?page=view");
				exit;
			}
		}
	}

	print $q->header("text/html; charset=utf-8");

	print $q->h1("Nowy wpis - $user{full_name}");

	print $q->start_form(-method => "POST");
	print $q->hidden('page', 'add_entry');
    print $q->p, $q->label('Typ: '),
		$q->popup_menu('entry_type', ['work', 'absence', 'vacation', 'meeting'],
          'work', \%entry_type_descriptions);
	my $start_time = int(time / 3600) * 3600 + 3600;
	print $q->p, $q->label('Data początkowa: '),
		$q->textfield('date_from', timestamp_to_userdate($start_time));
	print $q->p, $q->label('Data końcowa: '),
		$q->textfield('date_to', timestamp_to_userdate($start_time + 7200));

	foreach(@errors) {
		print "<p style=\"color: red;\">$_</p>";
	}
		
	print $q->p, $q->submit(-value => "Dodaj");
	print $q->end_form();
}

my $page = $q->param("page");

my %pages = (
	"view" => sub { page_view_calendar(); },
	"add_entry" => sub { page_add_entry(); }
);

$pages{$page}();
