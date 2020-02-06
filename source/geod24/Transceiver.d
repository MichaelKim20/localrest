/*******************************************************************************

    This is the interface needed to pass messages between threads and threads.
    Add ‘Channel’ for the data type and inherit this interface to create
    a new class.

*******************************************************************************/

module geod24.Transceiver;

import geod24.concurrency;

/// Ditto
public interface Transceiver
{

    /***************************************************************************

        It is a function that accepts Message

        Params:
            msg = The message to send.

    ***************************************************************************/

    void send (T) (T msg);


    /***************************************************************************

        Return the received message.

        Returns:
            A received message

    ***************************************************************************/

    T receive (T) ();


    /***************************************************************************

        Return the received message.

        Params:
            msg = The message pointer to receive.

        Returns:
            Returns true when message has been received. Otherwise false

    ***************************************************************************/

    bool tryReceive (T) (T *msg);


    /***************************************************************************

        Close the `Channel`

    ***************************************************************************/

    void close ();


    /***************************************************************************

        Return closing status

        Return:
            true if channel is closed, otherwise false

    ***************************************************************************/

    @property bool isClosed ();


    /***************************************************************************

        Generate a convenient string for identifying this Transceiver.

    ***************************************************************************/

    void toString (scope void delegate(const(char)[]) sink);
}
