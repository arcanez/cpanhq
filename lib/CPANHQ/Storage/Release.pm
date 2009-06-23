package CPANHQ::Storage::Release;

use strict;
use warnings;

=head1 NAME

CPANHQ::Storage::Release - a class representing a CPANHQ release

=head1 SYNOPSIS
      
    my $schema = CPANHQ->model("DB");

    my $releases_rs = $schema->resultset('Release');

    my $module_build_release = $releases_rs->find({
        distribution_id => $schema->resultset('Distribution')->find(
            {
                name => "Module-Build",
            })->id(),
        version => "0.33",
    );

    # Prints "Module-Build"
    print $module_build_release->distribution()->name();

    print $module_build_release->release_date();

    # Prints "EWILHELM"
    print $module_build_release->author()->cpanid();

=head1 DESCRIPTION

This is the release schema class for L<CPANHQ>.

=head1 METHODS

=cut

use base qw( DBIx::Class );

use File::Spec;
use List::Util qw(first);
use File::Temp qw(tempdir);

use CPAN::Mini;
use Archive::Extract;
use YAML::XS;

__PACKAGE__->load_components( qw( InflateColumn::DateTime Core ) );
__PACKAGE__->table( 'release' );
__PACKAGE__->add_columns(
    id => {
        data_type         => 'bigint',
        is_auto_increment => 1,
        is_nullable       => 0,
    },
    distribution_id => {
        data_type      => 'bigint',
        is_nullable    => 0,
        is_foreign_key => 1,
    },
    license_id => {
        data_type      => 'bigint',
        is_nullable    => 1,
        is_foreign_key => 1,
    },
    version => {
        data_type   => 'varchar',
        size        => 32,
        is_nullable => 1,
    },
    developer_release => {
        data_type     => 'boolean',
        default_value => 0,
        is_nullable   => 0,
    },
    path => {
        data_type   => 'varchar',
        size        => 255,
        is_nullable => 0,
    },
    size => {
        data_type   => 'bigint',
        is_nullable => 1,
    },
    author_id => {
        data_type      => 'bigint',
        is_nullable    => 0,
        is_foreign_key => 1,
    },
    release_date => {
        data_type   => 'datetime',
        is_nullable => 0,
    },
    abstract => {
        data_type   => 'varchar',
        size        => 512,
        is_nullable => 1,
    },
    homepage => {
        data_type   => 'varchar',
        size        => 512,
        is_nullable => 1,
    },
    mailing_list => {
        data_type   => 'varchar',
        size        => 512,
        is_nullable => 1,
    },
    vcs_repository => {
        data_type   => 'varchar',
        size        => 1024,
        is_nullable => 1,
    },
);

__PACKAGE__->set_primary_key( qw( id ) );
__PACKAGE__->resultset_attributes( { order_by => [ 'release_date DESC' ] } );
__PACKAGE__->belongs_to(
    distribution => 'CPANHQ::Storage::Distribution',
    'distribution_id'
);
__PACKAGE__->belongs_to( author => 'CPANHQ::Storage::Author', 'author_id' );
__PACKAGE__->belongs_to( license => 'CPANHQ::Storage::License', 'license_id' );
__PACKAGE__->add_unique_constraint( [ qw( distribution_id version ) ] );

=head2 $release->name()

Returns the distribution name and version.

=cut

sub name {
    my $self = shift;
    return join( ' ', $self->distribution->name, $self->version || '' );
}

=head2 $release->_get_meta_yml()

Reads the META.yml associated with this release and returns it.

May throw an exception.

=cut

sub _get_meta_yml {
    my $self = shift;

    my %config = CPAN::Mini->read_config;
    my $minicpan_path = 
        $config{'local'}
        ;

    my $fn_base = $self->distribution->name() . "-" . $self->version();
    my $author = $self->author->cpanid();

    my $arc_path =
        File::Spec->catfile(
            $minicpan_path,
            "authors",
            "id",
            substr($author, 0, 1),
            substr($author, 0, 2),
            $author,
            $fn_base . ".tar.gz",
        );

    if (! -e $arc_path)
    {
        die "Archive path '$arc_path' not found";
    }

    my $ae = Archive::Extract->new( archive => $arc_path );

    my $to_path = tempdir();

    my $ok = $ae->extract( to => $to_path )
        or die $ae->error();

    my $files = $ae->files();

    my $meta_yml_file = first { m{META\.yml\z}i } @$files;

    if (!defined ($meta_yml_file))
    {
        die "Could not find META.yml in archive '$arc_path'";
    }

    my $meta_yml_full_path = File::Spec->catfile(
        $to_path, $meta_yml_file
    );

    my ($yaml) = YAML::XS::LoadFile($meta_yml_full_path);

    return $yaml;
}

=head2 $self->_process_meta_yml()

Processes the META.yml (as returned by _get_meta_yml() ) and fills the
appropriate fields in the database.

=cut

sub _process_meta_yml {
    my $self = shift;

    my $meta_yml = $self->_get_meta_yml();

    if (my $license = $meta_yml->{'license'}) {
        $self->license(
            $self->result_source->schema->resultset('License')->find(
                {
                    string_id => $license,
                }
            )
        );
    }

    if (defined(my $abstract = $meta_yml->{'abstract'})) {
        $self->abstract($abstract);
    }

    if (defined(my $resources = $meta_yml->{'resources'}))
    {
        my %res_to_db =
        (
            homepage => "homepage",
            MailingList => "mailing_list",
            repository => "vcs_repository",
        );

        while (my ($res, $db_key) = each(%res_to_db))
        {
            if (defined(my $res_val = $resources->{$res})) {
                $self->$db_key($res_val);
            }
        }
    }
}

=head1 SEE ALSO

L<CPANHQ::Storage>, L<CPANHQ>, L<DBIx::Class>

=head1 AUTHOR

Brian Cassidy E<lt>bricas@cpan.orgE<gt>

Shlomi Fish L<http://www.shlomifish.org/> (who places all his contributions
and modifications under the public domain - 
L<http://creativecommons.org/license/zero> )

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
