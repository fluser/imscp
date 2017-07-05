=head1 NAME

 iMSCP::EventManager - i-MSCP Event Manager

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2017 by Laurent Declercq <l.declercq@nuxwin.com>
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

package iMSCP::EventManager;

use strict;
use warnings;
use autouse Clone => qw/ clone /;
use iMSCP::Debug;
use iMSCP::EventManager::ListenerPriorityQueue;
use Scalar::Util qw / blessed /;
use parent 'Common::SingletonClass';

=head1 DESCRIPTION

 The i-MSCP event manager is the central point of the event system.

 Event listeners are registered on the event manager and events are triggered through the event manager. Event
 listeners are references to subroutines that listen to particular event(s).

=head1 PUBLIC METHODS

=over 4

=item register( $eventNames, $listener [, priority = 1 [, $once = FALSE ] ] )

 Registers an event listener for the given events

 Param string|arrayref $eventNames Event(s) that the listener listen to
 Param subref|object $listener A subroutine reference or object implementing $eventNames method
 Param int $priority OPTIONAL Listener priority (Highest values have highest priority)
 PARAM bool $once OPTIONAL If TRUE, $listener will be executed at most once for the given events
 Return int 0 on success, 1 on failure

=cut

sub register
{
    my ($self, $eventNames, $listener, $priority, $once) = @_;

    local $@;
    eval {
        defined $eventNames or die '$eventNames parameter is not defined';

        if (ref $eventNames eq 'ARRAY') {
            $self->register( $_, $listener, $priority ) for @{$eventNames};
            return 0;
        }

        unless ($self->{'events'}->{$eventNames}) {
            $self->{'events'}->{$eventNames} = iMSCP::EventManager::ListenerPriorityQueue->new( );
        }

        $listener = sub { $listener->$eventNames( @_ ) } if blessed $listener;
        $self->{'events'}->{$eventNames}->addListener( $listener, $priority );
        $self->{'nonces'}->{$listener} = 1 if $once;
    };
    if ($@) {
        error($@);
        return 1;
    }

    0;
}

=item registerOne( $eventNames, $listener [, priority = 1 ] )

 Registers an event listener that will be executed at most once for the given events
 
 This is shortcut method for ::register( $eventNames, $listener, $priority, $once )

 Param string|arrayref $eventNames Event(s) that the listener listen to
 Param subref|object $listener A subroutine reference or object implementing $eventNames method
 Param int $priority OPTIONAL Listener priority (Highest values have highest priority)
 Return int 0 on success, 1 on failure

=cut

sub registerOne
{
    my ($self, $eventNames, $listener, $priority) = @_;

    $self->register( $eventNames, $listener, $priority, 1 );
}

=item unregister( $listener [, $eventName = undef ] )

 Unregister the given listener from all or the given event

 Param subref $listener Listener
 Param string $eventName Event name
 Return int 0 on success, 1 on failure

=cut

sub unregister
{
    my ($self, $listener, $eventName) = @_;

    local $@;
    eval {
        defined $listener or die '$listener parameter is not defined';

        if (defined $eventName) {
            $self->{'events'}->{$eventName}->removeListener( $listener ) if $self->{'events'}->{$eventName};
        } else {
            $_->removeListener( $listener ) for values %{$self->{'events'}};
        }
    };
    if ($@) {
        error($@);
        return 1;
    }

    0;
}

=item clearListeners( $eventName )

 Clear all listeners for the given event

 Param string $event Event name
 Return int 0 on success, 1 on failure

=cut

sub clearListeners
{
    my ($self, $eventName) = @_;

    unless (defined $eventName) {
        error( '$eventName parameter is not defined' );
        return 1;
    }

    delete $self->{'events'}->{$eventName};
    0;
}

=item trigger( $eventName [, @params ] )

 Triggers the given event

 Param string $eventName Event name
 Param mixed @params OPTIONAL parameters passed-in to the listeners
 Return int 0 on success, other on failure

=cut

sub trigger
{
    my ($self, $eventName, @params) = @_;

    unless (defined $eventName) {
        error( '$eventName parameter is not defined' );
        return 1;
    }

    return 0 unless $self->{'events'}->{$eventName};
    debug( sprintf( 'Triggering %s event', $eventName ) );

    # The priority queue acts as a heap, which implies that as items are popped
    # they are also removed. Thus we clone it for purposes of iteration.
    my $listenerPriorityQueue = clone( $self->{'events'}->{$eventName} );
    while(my $listener = $listenerPriorityQueue->pop( )) {
        my $rs = $listener->( @params );
        return $rs if $rs;

        if ($self->{'nonces'}->{$listener}) {
            $self->{'events'}->{$eventName}->removeListener( $listener );
            delete $self->{'nonces'}->{$listener};
        }
    }

    delete $self->{'events'}->{$eventName} if $self->{'events'}->{$eventName}->isEmpty( );
    0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init( )

 Initialize instance

 Return iMSCP::EventManager

=cut

sub _init
{
    my ($self) = @_;

    $self->{'events'} = { };
    $self->{'nonces'} = { };

    for (glob "$main::imscpConfig{'CONF_DIR'}/listeners.d/*.pl") {
        debug( sprintf( 'Loading %s listener file', $_ ) );
        require $_;
    }

    $self;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
