=head1 NAME

 iMSCP::Packages::Setup::AntiRootkits - i-MSCP Anti-Rootkits package

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 by Laurent Declercq <l.declercq@nuxwin.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

package iMSCP::Packages::Setup::AntiRootkits;

use strict;
use warnings;
use autouse 'iMSCP::Dialog::InputValidation' => qw/ isOneOfStringsInList /;
use File::Basename;
use iMSCP::Debug qw / debug error /;
use iMSCP::Dialog;
use iMSCP::Dir;
use iMSCP::Execute qw/ execute /;
use iMSCP::Getopt;
use version;
use parent 'iMSCP::Common::Singleton';

=head1 DESCRIPTION

 i-MSCP Anti-Rootkits package.

 Handles Anti-Rootkits packages found in the AntiRootkits directory.

=head1 PUBLIC METHODS

=over

=item registerSetupListeners( )

 Register setup event listeners

 Return void, die on failure

=cut

sub registerSetupListeners
{
    my ($self) = @_;

    $self->{'eventManager'}->registerOne( 'beforeSetupDialog', sub { push @{$_[0]}, sub { $self->showDialog( @_ ) }; } );
}

=item askAntiRootkits(\%dialog)

 Show dialog

 Param iMSCP::Dialog \%dialog
 Return int 0 or 30, die on failure

=cut

sub showDialog
{
    my ($self, $dialog) = @_;

    @{$self->{'SELECTED_PACKAGES'}} = split (
        ',', main::setupGetQuestion( 'ANTI_ROOTKITS_PACKAGES', iMSCP::Getopt->preseed ? join( ',', @{$self->{'AVAILABLE_PACKAGES'}} ) : '' )
    );

    my %choices;
    @choices{@{$self->{'AVAILABLE_PACKAGES'}}} = @{$self->{'AVAILABLE_PACKAGES'}};

    if ( isOneOfStringsInList( iMSCP::Getopt->reconfigure, [ 'antirootkits', 'all', 'forced' ] )
        || !@{$self->{'SELECTED_PACKAGES'}}
        || grep { !exists $choices{$_} && $_ ne 'no' } @{$self->{'SELECTED_PACKAGES'}}
    ) {
        ( my $rs, $self->{'SELECTED_PACKAGES'} ) = $dialog->checkbox(
            <<"EOF", \%choices, grep { exists $choices{$_} && $_ ne 'no' } @{$self->{'SELECTED_PACKAGES'}} );
Please select the Anti-Rootkits packages you want to install:
\\Z \\Zn
EOF
        push @{$self->{'SELECTED_PACKAGES'}}, 'no' unless @{$self->{'SELECTED_PACKAGES'}};
        return $rs unless $rs < 30;
    }

    main::setupSetQuestion( 'ANTI_ROOTKITS_PACKAGES', join ',', @{$self->{'SELECTED_PACKAGES'}} );

    return 0 if $self->{'SELECTED_PACKAGES'}->[0] eq 'no';

    for ( @{$self->{'SELECTED_PACKAGES'}} ) {
        my $package = "iMSCP::Packages::Setup::AntiRootkits::${_}::${_}";
        eval "require $package" or die( $@ );
        ( my $subref = $package->can( 'showDialog' ) ) or next;
        debug( sprintf( 'Executing showDialog action on %s', $package ));
        my $rs = $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ), $dialog );
        return $rs if $rs;
    }

    0;
}

=item preinstall( )

 Process preinstall tasks

 /!\ This method also trigger uninstallation of unselected Anti-Rootkits packages.

 Return void, die on failure

=cut

sub preinstall
{
    my ($self) = @_;

    my @distroPackages = ();
    for my $package( @{$self->{'AVAILABLE_PACKAGES'}} ) {
        next if grep( $package eq $_, @{$self->{'SELECTED_PACKAGES'}});
        $package = "iMSCP::Packages::Setup::AntiRootkits::${package}::${package}";
        eval "require $package" or die( $@ );

        if ( my $subref = $package->can( 'uninstall' ) ) {
            debug( sprintf( 'Executing uninstall action on %s', $package ));
            $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
        }

        ( my $subref = $package->can( 'getDistroPackages' ) ) or next;
        debug( sprintf( 'Executing getDistroPackages action on %s', $package ));
        push @distroPackages, $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
    }

    $self->_removePackages( @distroPackages );

    @distroPackages = ();
    for ( @{$self->{'SELECTED_PACKAGES'}} ) {
        my $package = "iMSCP::Packages::Setup::AntiRootkits::${_}::${_}";
        eval "require $package" or die( $@ );

        if ( my $subref = $package->can( 'preinstall' ) ) {
            debug( sprintf( 'Executing preinstall action on %s', $package ));
            $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
        }

        ( my $subref = $package->can( 'getDistroPackages' ) ) or next;
        debug( sprintf( 'Executing getDistroPackages action on %s', $package ));
        push @distroPackages, $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
    }

    $self->_installPackages( @distroPackages );
}

=item install( )

 Process install tasks

 Return void, die on failure

=cut

sub install
{
    my ($self) = @_;

    for ( @{$self->{'SELECTED_PACKAGES'}} ) {
        my $package = "iMSCP::Packages::Setup::AntiRootkits::${_}::${_}";
        eval "require $package" or die( $@ );
        ( my $subref = $package->can( 'install' ) ) or next;
        debug( sprintf( 'Executing install action on %s', $package ));
        $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
    }
}

=item postinstall( )

 Process post install tasks

 Return void, die on failure

=cut

sub postinstall
{
    my ($self) = @_;

    for ( @{$self->{'SELECTED_PACKAGES'}} ) {
        my $package = "iMSCP::Packages::Setup::AntiRootkits::${_}::${_}";
        eval "require $package" or die( $@ );
        ( my $subref = $package->can( 'postinstall' ) ) or next;
        debug( sprintf( 'Executing postinstall action on %s', $package ));
        $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
    }
}

=item uninstall( )

 Process uninstall tasks

 Return void, die on failure

=cut

sub uninstall
{
    my ($self) = @_;

    my @distroPackages = ();
    for ( @{$self->{'SELECTED_PACKAGES'}} ) {
        my $package = "iMSCP::Packages::Setup::AntiRootkits::${_}::${_}";
        eval "require $package" or die( $@ );

        if ( my $subref = $package->can( 'uninstall' ) ) {
            debug( sprintf( 'Executing preinstall action on %s', $package ));
            $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
        }

        ( my $subref = $package->can( 'getDistroPackages' ) ) or next;
        debug( sprintf( 'Executing getDistroPackages action on %s', $package ));
        push @distroPackages, $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
    }

    $self->_removePackages( @distroPackages );
}

=item getPriority( )

 Get package priority

 Return int package priority

=cut

sub getPriority
{
    0;
}

=item setEnginePermissions( )

 Set engine permissions

 Return void, die on failure

=cut

sub setEnginePermissions
{
    my ($self) = @_;

    for ( @{$self->{'SELECTED_PACKAGES'}} ) {
        my $package = "iMSCP::Packages::Setup::AntiRootkits::${_}::${_}";
        eval "require $package" or die( $@ );
        ( my $subref = $package->can( 'setEnginePermissions' ) ) or next;
        debug( sprintf( 'Executing setEnginePermissions action on %s', $package ));
        $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
    }
}

=item setGuiPermissions( )

 Set gui permissions

 Return void, die on failure

=cut

sub setGuiPermissions
{
    my ($self) = @_;

    for ( @{$self->{'SELECTED_PACKAGES'}} ) {
        my $package = "iMSCP::Packages::Setup::AntiRootkits::${_}::${_}";
        eval "require $package" or die( $@ );
        ( my $subref = $package->can( 'setGuiPermissions' ) ) or next;
        debug( sprintf( 'Executing setGuiPermissions action on %s', $package ));
        $subref->( $package->getInstance( eventManager => $self->{'eventManager'} ));
    }
}

=back

=head1 PRIVATE METHODS

=over 4

=item init( )

 Initialize instance

 Return iMSCP::Packages::Setup::AntiRootkits, die on failure

=cut

sub _init
{
    my ($self) = @_;

    @{$self->{'AVAILABLE_PACKAGES'}} = iMSCP::Dir->new( dirname => dirname( __FILE__ ) . '/AntiRootkits' )->getDirs();
    @{$self->{'SELECTED_PACKAGES'}} = grep( $_ ne 'no', split( ',', $main::imscpConfig{'ANTI_ROOTKITS_PACKAGES'} ));
    $self;
}

=item _installPackages( @packages )

 Install distribution packages

 Param list @packages List of distribution packages to install
 Return void, die on failure

=cut

sub _installPackages
{
    my (undef, @packages) = @_;

    return unless @packages && !iMSCP::Getopt->skippackages;

    iMSCP::Dialog->getInstance->endGauge() unless iMSCP::Getopt->noprompt;

    local $ENV{'LANG'} = 'C';
    local $ENV{'UCF_FORCE_CONFFNEW'} = 1;
    local $ENV{'UCF_FORCE_CONFFMISS'} = 1;

    my $stdout;
    my $rs = execute(
        [
            ( !iMSCP::Getopt->noprompt ? ( 'debconf-apt-progress', '--logstderr', '--' ) : () ),
            'apt-get', '--assume-yes', '--option', 'DPkg::Options::=--force-confnew', '--option',
            'DPkg::Options::=--force-confmiss', '--option', 'Dpkg::Options::=--force-overwrite',
            ( iMSCP::Getopt->forcereinstall ? '--reinstall' : () ), '--auto-remove', '--purge', '--no-install-recommends',
            ( version->parse( `apt-get --version 2>/dev/null` =~ /^apt\s+(\d\.\d)/ ) < version->parse( '1.1' )
                ? '--force-yes' : '--allow-downgrades' ),
            'install', @packages
        ],
        ( iMSCP::Getopt->noprompt && !iMSCP::Getopt->verbose ? \$stdout : undef ),
        \ my $stderr
    );
    !$rs or die( sprintf( "Couldn't install packages: %s", $stderr || 'Unknown error' ));
}

=item _removePackages( @packages )

 Remove distribution packages

 Param list @packages Packages to remove
 Return void, die on failure

=cut

sub _removePackages
{
    my (undef, @packages) = @_;

    return unless @packages && !iMSCP::Getopt->skippackages;

    # Do not try to remove packages that are not available
    execute( "dpkg-query -W -f='\${Package}\\n' @packages 2>/dev/null", \ my $stdout );
    @packages = split /\n/, $stdout;
    return unless @packages;

    iMSCP::Dialog->getInstance()->endGauge() unless iMSCP::Getopt->noprompt;

    my $rs = execute(
        [
            ( !iMSCP::Getopt->noprompt ? ( 'debconf-apt-progress', '--logstderr', '--' ) : () ),
            'apt-get', '--assume-yes', '--auto-remove', '--purge', '--no-install-recommends', 'remove', @packages
        ],
        ( iMSCP::Getopt->noprompt && !iMSCP::Getopt->verbose ? \ $stdout : undef ),
        \my $stderr
    );
    !$rs or die( sprintf( "Couldn't remove packages: %s", $stderr || 'Unknown error' ));
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__