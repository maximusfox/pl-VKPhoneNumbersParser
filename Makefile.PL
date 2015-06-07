use strict;
use warnings;
 
use ExtUtils::MakeMaker;
 
WriteMakefile(
  NAME          => 'VKPhoneNambersParser',
  AUTHOR        => 'SHok',
  LICENSE       => 'perl_5',
  PREREQ_PM     => {
    'Coro' => 6.41,
    'Coro::LWP' => 6.41,
    'Coro::Select' => 6.41,
    'Coro::Timer' => 6.41,

    'LWP::UserAgent' => 6.06,
    'Getopt::Args' => 0.1.14,
    'DBIx::Custom' => 0.30,
    'JSON::XS' => 3.01,
  }
);