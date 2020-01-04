/*******************************************************************************

    This is an abstract of the transmission and reception module of the message.
    Send and receive messages using the Channel in `geod24.concurrency`.
    Fiber

    It is the Scheduler that allows the channel to connect the fiber organically.

*******************************************************************************/

module geod24.Transceiver;

import geod24.concurrency;

import core.time;


/// Data sent by the caller
public struct Request
{
    /// ITransceiver of the sender thread
    ITransceiver sender;

    /// In order to support re-entrancy, every request contains an id
    /// which should be copied in the `Response`
    /// Initialized to `size_t.max` so not setting it crashes the program
    size_t id;

    /// Method to call
    string method;

    /// Arguments to the method, JSON formatted
    string args;
};


/// Status of a request
public enum Status
{
    /// Request failed
    Failed,

    /// Request timed-out
    Timeout,

    /// Request Dropped
    Dropped,

    /// Request succeeded
    Success
};


/// Data sent by the callee back to the caller
public struct Response
{
    /// Final status of a request (failed, timeout, success, etc)
    Status status;
    /// In order to support re-entrancy, every request contains an id
    /// which should be copied in the `Response` so the scheduler can
    /// properly dispatch this event
    /// Initialized to `size_t.max` so not setting it crashes the program
    size_t id;
    /// If `status == Status.Success`, the JSON-serialized return value.
    /// Otherwise, it contains `Exception.toString()`.
    string data;
};

/// Filter out requests before they reach a node
public struct FilterAPI
{
    /// the mangled symbol name of the function to filter
    string func_mangleof;

    /// used for debugging
    string pretty_func;
}

/// Ask the node to exhibit a certain behavior for a given time
public struct TimeCommand
{
    /// For how long our remote node apply this behavior
    Duration dur;
    /// Whether or not affected messages should be dropped
    bool drop = false;
}

/// Ask the node to shut down
public struct ShutdownCommand
{
}

/// Status of a request
public enum MessageType
{
    request,
    response,
    filter,
    time_command,
    shutdown_command
};

// very simple & limited variant, to keep it performant.
// should be replaced by a real Variant later
static struct Message
{
    this (Request msg) { this.req = msg; this.tag = MessageType.request; }
    this (Response msg) { this.res = msg; this.tag = MessageType.response; }
    this (FilterAPI msg) { this.filter = msg; this.tag = MessageType.filter; }
    this (TimeCommand msg) { this.time = msg; this.tag = MessageType.time_command; }
    this (ShutdownCommand msg) { this.shutdown = msg; this.tag = MessageType.shutdown_command; }

    union
    {
        Request req;
        Response res;
        FilterAPI filter;
        TimeCommand time;
        ShutdownCommand shutdown;
    }

    ubyte tag;
}

/*******************************************************************************

    Receve request and response
    Interfaces to and from data

*******************************************************************************/

public interface ITransceiver
{
    /***************************************************************************

        It is a function that accepts `Request`.

    ***************************************************************************/

    void send (Request msg);


    /***************************************************************************

        It is a function that accepts `Response`.

    ***************************************************************************/

    void send (Response msg);


    /***************************************************************************

        Generate a convenient string for identifying this ServerTransceiver.

    ***************************************************************************/

    void toString (scope void delegate(const(char)[]) sink);
}


/*******************************************************************************

    Accept only Request. It has `Channel!Request`

*******************************************************************************/

public class ServerTransceiver : ITransceiver
{
    /// Channel of Request
    public Channel!Message chan;

    /// Ctor
    public this () @safe nothrow
    {
        chan = new Channel!Message();
    }


    /***************************************************************************

        It is a function that accepts `Request`.

    ***************************************************************************/

    public void send (Request msg) @trusted
    {
        if (thisScheduler !is null)
            this.chan.send(Message(msg));
        else
        {
            auto fiber_scheduler = new FiberScheduler();
            auto condition = fiber_scheduler.newCondition(null);
            fiber_scheduler.start({
                this.chan.send(Message(msg));
                condition.notify();
            });
            condition.wait();
        }
    }


    /***************************************************************************

        It is a function that accepts `TimeCommand`.

    ***************************************************************************/

    public void send (TimeCommand msg) @trusted
    {
        if (thisScheduler !is null)
            this.chan.send(Message(msg));
        else
        {
            auto fiber_scheduler = new FiberScheduler();
            auto condition = fiber_scheduler.newCondition(null);
            fiber_scheduler.start({
                this.chan.send(Message(msg));
                condition.notify();
            });
            condition.wait();
        }
    }


    /***************************************************************************

        It is a function that accepts `TimeCommand`.

    ***************************************************************************/

    public void send (ShutdownCommand msg) @trusted
    {
        if (thisScheduler !is null)
            this.chan.send(Message(msg));
        else
        {
            auto fiber_scheduler = new FiberScheduler();
            auto condition = fiber_scheduler.newCondition(null);
            fiber_scheduler.start({
                this.chan.send(Message(msg));
                condition.notify();
            });
            condition.wait();
        }
    }


    /***************************************************************************

        It is a function that accepts `FilterAPI`.

    ***************************************************************************/

    public void send (FilterAPI msg) @trusted
    {
        if (thisScheduler !is null)
            this.chan.send(Message(msg));
        else
        {
            auto fiber_scheduler = new FiberScheduler();
            auto condition = fiber_scheduler.newCondition(null);
            fiber_scheduler.start({
                this.chan.send(Message(msg));
                condition.notify();
            });
            condition.wait();
        }
    }


    /***************************************************************************

        It is a function that accepts `Response`.

    ***************************************************************************/

    public void send (Response msg) @trusted
    {
        if (thisScheduler !is null)
            this.chan.send(Message(msg));
        else
        {
            auto fiber_scheduler = new FiberScheduler();
            auto condition = fiber_scheduler.newCondition(null);
            fiber_scheduler.start({
                this.chan.send(Message(msg));
                condition.notify();
            });
            condition.wait();
        }
    }


    /***************************************************************************

        Close the `Channel`

    ***************************************************************************/

    public void close () @trusted
    {
        this.chan.close();
    }


    /***************************************************************************

        Generate a convenient string for identifying this ServerTransceiver.

    ***************************************************************************/

    public void toString (scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;
        formattedWrite(sink, "STR(%x)", cast(void*) chan);
    }
}


/*******************************************************************************

    Accept only Response. It has `Channel!Response`

*******************************************************************************/

public class ClientTransceiver : ITransceiver
{
    /// Channel of Response
    public Channel!Message chan;

    /// Ctor
    public this () @safe nothrow
    {
        chan = new Channel!Message();
    }


    /***************************************************************************

        It is a function that accepts `Request`.
        It is not use.

    ***************************************************************************/

    public void send (Request msg) @trusted
    {
    }


    /***************************************************************************

        It is a function that accepts `Response`.

    ***************************************************************************/

    public void send (Response msg) @trusted
    {
        if (thisScheduler !is null)
            this.chan.send(Message(msg));
        else
        {
            auto fiber_scheduler = new FiberScheduler();
            auto condition = fiber_scheduler.newCondition(null);
            fiber_scheduler.start({
                this.chan.send(Message(msg));
                condition.notify();
            });
            condition.wait();
        }
    }


    /***************************************************************************

        Close the `Channel`

    ***************************************************************************/

    public void close () @trusted
    {
        this.chan.close();
    }


    /***************************************************************************

        Generate a convenient string for identifying this ServerTransceiver.

    ***************************************************************************/

    public void toString (scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;
        formattedWrite(sink, "CTR(%x)", cast(void*) chan);
    }
}

