=head1 NAME

 iMSCP::Servers::Mta::Postfix::Driver::Database::Hash - i-MSCP hash database driver for Postfix

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 Laurent Declercq <l.declercq@nuxwin.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

package iMSCP::Servers::Mta::Postfix::Driver::Database::Hash;

use strict;
use warnings;
use autouse 'iMSCP::Rights' => qw/ setRights /;
use Class::Autouse qw/ :nostat iMSCP::Dir /;
use iMSCP::File;
use iMSCP::Boolean;
use parent 'iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract';

=head1 DESCRIPTION

 i-MSCP hash database driver for Postfix.
 
 See http://www.postfix.org/DB_README.html

=head1 PUBLIC METHODS

=over 4

=item preinstall( )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::preinstall()

=cut

sub install
{
    my ( $self ) = @_;

    $self->_setupDatabases();
}

=item uninstall( )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::uninstall()

=cut

sub uninstall
{
    my ( $self ) = @_;

    iMSCP::Dir->new( dirname => $self->{'mta'}->{'config'}->{'MTA_DB_DIR'} )->remove();
}

=item setEnginePermissions( )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::setEnginePermissions()

=cut

sub setEnginePermissions
{
    my ( $self ) = @_;

    setRights( $self->{'mta'}->{'config'}->{'MTA_DB_DIR'},
        {
            user      => $::imscpConfig{'ROOT_USER'},
            group     => $::imscpConfig{'ROOT_GROUP'},
            dirmode   => '0750',
            filemode  => '0640',
            recursive => 1
        }
    );
}

=item add( $database [, $key [, $value = 'OK, [ $storagePath = $self->{'mta'}->{'config'}->{'MTA_DB_DIR'} ] ] ] )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::add()

=cut

sub add
{
    my ( $self, $database, $key, $value, $storagePath ) = @_;

    defined $database or die( '$database parameter is missing' );

    my $file = $self->_getDbFileObj( $database, $storagePath );

    return unless defined $key;

    my $entry = "$key\t@{ [ $value //= 'OK' ] }";
    my $mapFileContentRef = $file->getAsRef();
    ${ $mapFileContentRef } =~ s/^\Q$entry\E\n//gim;
    ${ $mapFileContentRef } .= "$entry\n";
    $file->save();
    $self;
}

=item delete( $database [, $key [, $storagePath = $self->{'mta'}->{'config'}->{'MTA_DB_DIR'} ] ] )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::delete()

=cut

sub delete
{
    my ( $self, $database, $key, $storagePath ) = @_;

    defined $database or die( '$database parameter is missing' );

    my $file = $self->_getDbFileObj( $database, $storagePath );

    unless ( defined $key ) {
        $file->remove();
        undef( $file );
        undef( $self->{'_db'}->{$database} );
        return;
    }

    my $mapFileContentRef = $file->getAsRef();
    $file->save() if ${ $mapFileContentRef } =~ s/^\Q$key\E\t.*\n//gim;
    $self;
}

=item getDbType( )

 See iMSCP::Server::Mta::Posfix::Driver::Database::Abstract::getDbType()

=cut

sub getDbType
{
    my ( $self ) = @_;

    'hash';
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init( )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::_init()

=cut

sub _init
{
    my ( $self ) = @_;

    ref $self ne __PACKAGE__ or croak( sprintf( 'The %s class is an abstract class which cannot be instantiated', __PACKAGE__ ));
    $self->{'_db'} = {};
    $self->SUPER::_init();
}

=item _getDbFileObj( $database [, $storagePath = $self->{'mta'}->{'config'}->{'MTA_DB_DIR'} ] )

 Get database file object for the given database

 If the given database doesn't exists yet, it will be created and a POSTMAP(1)
 will be scheduled.
 
 TODO: Load file into hash for faster processing (using Config::General module?)

 Param string $database Database name
 Param string storagePath OPTIOANL Storage path
 Return iMSCP::File, die on failure

=cut

sub _getDbFileObj
{
    my ( $self, $database, $storagePath ) = @_;
    $storagePath //= $self->{'mta'}->{'config'}->{'MTA_DB_DIR'};

    $self->{'_db'}->{$storagePath / $database} ||= do {
        my $file = iMSCP::File->new( filename => "$storagePath/$database" );

        unless ( -f $file ) {
            $file->set( <<"EOF"
# Postfix $database database - auto-generated by i-MSCP
#     DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN

EOF
            )->save( 0027 );
        }

        # Schedule postmap of this database
        $self->{'mta'}->postmap( "$storagePath/$database", $self->getDbType(), TRUE );

        # Preload table in memory
        # We need raise default slurp limit since default value (2 MiB) is far too low.
        # Default limit for DB slurp is 10 MiB in the conffile. This should be far enough
        # because table with 10k entries take ~ 2 MiB.
        local $iMSCP::File::SLURP_SIZE_LIMIT = $self->{'mta'}->{'config'}->{'MTA_DB_SLURP_LIMIT'};
        $file->getAsRef();
        $file;
    }
}

=item _setupDatabases( )

 Setup default databases

 Return void, die on failure

=cut

sub _setupDatabases
{
    my ( $self ) = @_;

    # Make sure to start with a clean directory by re-creating it from scratch
    iMSCP::Dir->new( dirname => $self->{'mta'}->{'config'}->{'MTA_DB_DIR'} )->remove()->make(
        {
            user  => $self->{'mta'}->{'config'}->{'MTA_MAILBOX_UID_NAME'},
            group => $self->{'mta'}->{'config'}->{'MTA_MAILBOX_GID_NAME'},
            mode  => 0750
        }
    );

    # Create empty databases
    for my $db ( qw/ virtual_mailbox_domains virtual_mailbox_maps virtual_alias_maps relay_domains transport_maps / ) {
        $self->add( $db );
    }

    # Add configuration in the main.cf file
    my $dbType = $self->getDbType();
    $self->{'mta'}->postconf(
        virtual_alias_domains   => { values => [ '' ] },
        virtual_alias_maps      => { values => [ "$dbType:$self->{'mta'}->{'config'}->{'MTA_DB_DIR'}/virtual_alias_maps" ] },
        virtual_mailbox_domains => { values => [ "$dbType:$self->{'mta'}->{'config'}->{'MTA_DB_DIR'}/virtual_mailbox_domains" ] },
        virtual_mailbox_maps    => { values => [ "$dbType:$self->{'mta'}->{'config'}->{'MTA_DB_DIR'}/virtual_mailbox_maps" ] },
        relay_domains           => { values => [ "$dbType:$self->{'mta'}->{'config'}->{'MTA_DB_DIR'}/relay_domains" ] },
        transport_maps          => { values => [ "$dbType:$self->{'mta'}->{'config'}->{'MTA_DB_DIR'}/transport_maps" ] }
    );
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
