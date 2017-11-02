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

my %user;

# 0. Basic auth
# 1. Display user's calendar
# 2. Add entry
# 3. Delete entry
# 4. Boss dashboard - status of each employee
# 5. Reserve meeting - given duration, list possible dates

my %entry_type_descriptions = (
  'work' => "Godziny pracy",
  'busy' => "Zajętość",
  'vacation' => "Urlop",
  'meeting' => "Spotkanie"
);

# userdate - string, "YYYY-MM-DD hh:mm"
# timestamp - seconds since Unix epoch

# Parse userdate.
# Returns undef on failure.
sub userdate_to_timestamp {
	my $date = shift @_;
	if($date =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/) {
		return mktime(0, $5, $4, $3, $2 - 1, $1 - 1900);
	} else {
		return undef;
	}
}

use Test::More;
is(userdate_to_timestamp("2017-11-02 21:49"),1509655740);
done_testing();

sub timestamp_to_userdate {
	my $time = shift @_;
	return strftime("%F %R", localtime($time));
}

# true if current user is a boss
sub is_boss {
	return $user{user_type} eq 'boss';
}

# can_delete_entry(entry : hashref) - whether the current user can delete an entry
# 
# The rules are as follows:
# - boss can delete everything
# - everyone can delete their own entries
sub can_delete_entry {
	my $entry = shift @_;
	return is_boss || $entry->{user_login} eq $user{login};
}

sub page_view_calendar {
	print $q->header("text/html; charset=utf-8");

	print $q->h1("Kalendarz - $user{full_name}");

	my $st = $dbh->prepare(q(
		SELECT * FROM calendar_entries
		WHERE user_login = ? OR user_login IS NULL
		ORDER BY date_from ASC
		));
	$st->execute($user{login});

	while(my $row = $st->fetchrow_hashref) {
		print "<div><hr/>";
		print $q->p($row->{date_from} . " &ndash; " . $row->{date_to});
		print $q->p($entry_type_descriptions{$row->{entry_type}});

		if(can_delete_entry($row)) {
			print $q->start_form(-method => "POST", -action => "?page=delete_entry");
			print q(<input type="hidden" name="page" value="delete_entry">);
			print $q->hidden('entry_id', $row->{entry_id});
			print $q->submit(-value => "Usuń");
			print $q->end_form();
		}

		print "</div>";
	}
	print "<hr/>";

	print q(<p><a href="?page=add_entry">Dodaj nowy wpis</a></p>);

	if(is_boss) {
		print q(<p><a href="?page=find_meeting_time">Znajdź termin spotkania</a></p>);
	}
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
			if($record{entry_type} ne 'meeting') {
				# meetings are for everyone
				$record{user_login} = $user{login};
			}
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

	my $types =
		is_boss ?
		['work', 'busy', 'vacation', 'meeting'] :
		['work', 'busy', 'vacation'];

    print $q->p, $q->label('Typ: '),
		$q->popup_menu('entry_type', $types,
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

sub page_delete_entry {
	my $entry_id = $q->param('entry_id');
	my $st = $dbh->prepare("SELECT * FROM calendar_entries WHERE entry_id = ?");
	$st->execute($entry_id);
	if(my $entry = $st->fetchrow_hashref) {
		if(can_delete_entry($entry)) {
			$st = $dbh->prepare("DELETE FROM calendar_entries WHERE entry_id = ?");
			$st->execute($entry_id);
			print $q->redirect("?page=view");
		} else {
			print $q->header(-status => "403 Forbidden");
			print "Can't delete this entry.";
			exit;
		}
	}
}

sub get_user_logins {
	my $st = $dbh->prepare("SELECT login FROM users");
	$st->execute();
	my $results = $st->fetchall_arrayref({});
	my @array = map { $_->{login} } @$results;
	return \@array;
}

sub potential_start_times {
	my $entries = shift @_;

	my @result = map {
		userdate_to_timestamp(
			($_->{entry_type} eq 'work') ?
				$_->{date_from} :
				$_->{date_to})
	} @$entries;
	return \@result;
}

sub is_at_work {
	my ($login, $entries, $when) = @_;
	return scalar grep {
		$_->{user_login} eq $login &&
		userdate_to_timestamp($_->{date_from}) <= $when->{date_from} &&
		userdate_to_timestamp($_->{date_to}) >= $when->{date_to}
	} @$entries;
}

# A meeting time is valid if:
# - all users are at work during the time
# - no user has vacation, is busy during the time
# - there's no meeting during the time
sub is_valid_meeting_time {
	my ($users, $entries, $when) = @_;
	my $any_user_not_at_work = grep { !is_at_work($_, $entries, $when) } @$users;
	if($any_user_not_at_work) {
		return 0;
	}

	my $any_absence = grep {
		$_->{entry_type} ne 'work' &&
		userdate_to_timestamp($_->{date_from}) <= $when->{date_from} &&
		userdate_to_timestamp($_->{date_to}) >= $when->{date_to}
	} @$entries;

	return !$any_absence;
}

sub page_find_meeting_time {
	unless(is_boss) {
		print $q->header(-status => "403 Forbidden");
		print "This page is only for the boss.";
		exit;
	}

	print $q->header("text/html; charset=utf-8");

	print $q->h1("Znajdź czas na spotkanie grupy roboczej");

	print $q->start_form(-method => "GET");
	print $q->hidden('page', 'find_meeting_time');
	print $q->p, $q->label('Czas trwania (godziny): '), $q->textfield('num_hours', 2);
	print $q->p, $q->submit(-value => "Szukaj");
	print $q->end_form();

	my $num_hours = $q->param('num_hours') || 2;

	my $duration_in_seconds = $num_hours * 3600;

	my $users = get_user_logins;
	
	my $st = $dbh->prepare("SELECT * FROM calendar_entries WHERE date_to > date('now') ORDER BY date_from ASC");
	$st->execute();
	my $entries = $st->fetchall_arrayref({});
	my $potential_start_times = potential_start_times($entries);
	unshift @$potential_start_times, time;

	my @meeting_times =
		grep { is_valid_meeting_time($users, $entries, $_) }
		map { my %h = ( "date_from" => $_, "date_to" => $_ + $duration_in_seconds ); \%h }
		@$potential_start_times;

	print "<ul>";
	foreach(@meeting_times) {
		my $date_from = timestamp_to_userdate($_->{date_from});
		my $date_to = timestamp_to_userdate($_->{date_to});
		print qq(
			<li>$date_from &ndash; $date_to 
		        <a href="?page=add_entry&entry_type=meeting&date_from=$date_from&date_to=$date_to">
				  Dodaj spotkanie</a>
		    </li>);
	}
	print "</ul>";
}

sub unauthorized {
	print $q->header(
		-status => "401 Unauthorized",
		"WWW-Authenticate" => "Basic realm=\"kalendarz\""
	);
	exit;
}

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

my $page = $q->param("page") || "view";

my %pages = (
	"view" => sub { page_view_calendar(); },
	"add_entry" => sub { page_add_entry(); },
	"delete_entry" => sub { page_delete_entry(); },
	"find_meeting_time" => sub { page_find_meeting_time(); },
);

$pages{$page}();
