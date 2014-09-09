#!/usr/bin/env perl

use utf8;
use strict;
use warnings;
use feature qw/say switch unicode_strings/;

use Coro;
use Coro::LWP;
use Coro::Select;
use Coro::Timer;

use LWP::UserAgent;
use Getopt::Args;
use DBIx::Custom;
use JSON::XS;

our $ATCcodes = {
	91 => 'Utel',
	92 => 'PeopleNET',
	94 => 'Intertelecom',
	50 => 'MTS',
	66 => 'MTS',
	95 => 'MTS',
	99 => 'MTS',
	39 => 'KievStar',
	96 => 'KievStar',
	67 => 'KievStar',
	97 => 'KievStar',
	68 => 'KievStar',
	98 => 'KievStar',
	93 => 'Life',
	63 => 'Life',
};

opt first => (
	isa     => 'Int',
	alias   => 'f',
	comment => 'First user ID',
);

opt last => (
	isa     => 'Int',
	alias   => 'l',
	comment => 'Last user ID',
);

opt db => (
	isa     => 'Str',
	alias   => 'd',
	comment => 'SQLite databse location',
);

opt threads => (
	isa     => 'Int',
	alias   => 't',
	default => 10,
	comment => 'Threads count',
);

opt help => (
	isa     => 'Bool',
	alias	=> 'h',
	comment => 'Show this help message',
	ishelp  => 1,
);

my $opts = optargs;
die usage() if ($opts->{help});


unless ($opts->{first}) {
	die usage('Not selected first user id!');
}

unless ($opts->{last}) {
	die usage('Not selected last user id!');
}

say '[*] ID reange selected: '.$opts->{first}.' - '.$opts->{last};


my $dbi;
unless ($opts->{db}) {
	if (-e 'main.sqlite') {
		say '[*] Connect to exist db main.sqlite';
		$dbi = DBIx::Custom->connect( dsn => "dbi:SQLite:dbname=main.sqlite" ) or die "Can't connect to database! $!";
	} else {
		say '[*] Create main.sqlite';
		`sqlite3 main.sqlite < sql/dump.sql`;

		say '[*] Connect to main.sqlite';
		$dbi = DBIx::Custom->connect( dsn => "dbi:SQLite:dbname=main.sqlite" ) or die "Can't connect to database! $!";
	}
} else {
	say '[*] Connect to exist db '.$opts->{db};
	$dbi = DBIx::Custom->connect( dsn => "dbi:SQLite:dbname=".$opts->{db}.'.sqlite' ) or die "Can't connect to database! $!";
}

my @coros;
my @usersID = ($opts->{first}..$opts->{last});
say '[*] Generated pull: '.scalar(@usersID);

for (1..$opts->{threads}) {
	push @coros, async {
		my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0 (X11; U; Linux i686; cs-CZ; rv:1.7.12) Gecko/20050929' );

		while (@usersID) {
			my $id = shift(@usersID);

			say '[+] User id exists: '.$id and next if (userExist($id));
			say '[i] User id not exists: '.$id;

			my $resp = $ua->get('https://api.vk.com/method/users.get?user_ids='.$id.'&fields=contacts,has_mobile,city');
			unless ($resp->is_success) {
				Coro::Timer::sleep(5);
				say '[!] Respons not success: '.$id;
				next;
			}

			my $jsonObject = decode_json($resp->content);
			unless (defined $jsonObject->{response}->[0]->{has_mobile} or defined $jsonObject->{response}->[0]->{city}) {
				say '[!] Not find mobile or city: '.$id;
				next;
			}

			unless ($jsonObject->{response}->[0]->{has_mobile} == 1) {
				say '[!] Not find mobile: '.$id;
				next;
			}


			my $phone = getPhone($ua, $id);
			say '[!] Not find phone: '.$id and next unless ($phone);

			$phone = reformatPhone($phone);
			say '[!] Not find phone after reformat: '.$id and next unless ($phone);

			my $operator = Operator($phone);
			say '[!] Not find operator: '.$phone and next unless ($operator);

			my $FirstName = $jsonObject->{response}->[0]->{first_name};
			my $LastName = $jsonObject->{response}->[0]->{last_name};
			my $City = $jsonObject->{response}->[0]->{city};
			my $CityName = (cityName($ua, $jsonObject->{response}->[0]->{city})||'UNDEF');

			$dbi->insert(
				{
					id => $id,
					FirstName => $FirstName,
					LastName => $LastName,
					Phone => $phone,
					RegionID => $City,
					Region => $CityName,
					Operator => $operator,
				},
				table  => 'UsersList',
			);

			if ($phone) {
				say '[+] https://vk.com/id'.$id.' - '.$phone;
			} else {
				say '[i] https://vk.com/id'.$id;
			}
		}
	}
}

$_->join for (@coros);

sub getPhone {
	my ($ua, $id) = @_;

	my $resp = $ua->get('https://vk.com/id'.$id);
	unless ($resp->is_success) {
		return undef;
	}

	if ($resp->content =~ m#<div class="labeled fl_l">([\+|\d+]+)</div>#) {
		return $1;
	}

	return undef;
}

sub Operator {
	my ($number) = @_;

	my ($country, $operator, $phone);
	if ( ($country, $operator, $phone) = $number =~ m#[\+]{0,1}(380)(\d{2})(\d{7})# ) {
		# say '[DBG] [380] Operator code: '.$operator;
		return $ATCcodes->{$operator};
	}

	if ( ($country, $operator, $phone) = $number =~ m#(80)(\d{2})(\d{7})# ) {
		# say '[DBG] [80] Operator code: '.$operator;
		return $ATCcodes->{$operator};
	}

	if ( ($country, $operator, $phone) = $number =~ m#(0)(\d{2})(\d{7})# ) {
		# say '[DBG] [0] Operator code: '.$operator;
		return $ATCcodes->{$operator};
	}

	# say '[DBG] [UNDEF] Operator code: '.$operator;
	return $ATCcodes->{$operator} if (defined $operator and exists $ATCcodes->{$operator});
}

sub reformatPhone {
	my ($number) = @_;

	my ($country, $operator, $phone);
	return undef unless ( ($country, $operator, $phone) = $number =~ m#[\+]{0,1}(380)(\d{2})(\d{7})# );
	return undef unless ( ($country, $operator, $phone) = $number =~ m#(80)(\d{2})(\d{7})# );
	return undef unless ( ($country, $operator, $phone) = $number =~ m#(0)(\d{2})(\d{7})# );

	# say '[DBG] [UNDEF] Operator code: '.$operator;
	return '+380'.$operator.$phone if (defined $operator and defined $phone);
	return undef;
}

sub cityName {
	my ($ua, $id) = @_;

	my $resp = $ua->get('https://api.vk.com/method/database.getCitiesById?city_ids='.$id);
	# say '[DBG] City name: '.$resp->content;
	unless ($resp->is_success) {
		return undef;
	}

	my $jsonObject = decode_json($resp->content);
	# say '[i] City name: '.$jsonObject->{response}->[0]->{name};
	return $jsonObject->{response}->[0]->{name} if ($jsonObject->{response}->[0]->{name});

	return undef;
}

sub userExist {
	my $result = $dbi->select(
		'id',
		table  => 'UsersList',
		where  => { id => $_[0] }
	);
	return undef unless ($result);

	my $row = $result->one;
	return undef unless ($row);

	return 1;
}