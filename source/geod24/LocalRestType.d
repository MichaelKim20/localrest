/*******************************************************************************

    There are various data that nodes need to exchange messages.
    Send and receive data requests, responses, commands, etc.
    MessageChannel is `Channel`, and exchange the `Message`.

*******************************************************************************/

module geod24.LocalRestType;

import geod24.concurrency;

import std.format;
import std.process;

import core.atomic;
import core.thread;
import core.time;

public alias MessageChannel = Channel!Message;

/// Data sent by the caller
public struct Command
{
    /// In order to support re-entrancy, every request contains an id
    /// which should be copied in the `Response`
    /// Initialized to `size_t.max` so not setting it crashes the program
    size_t id = size_t.max;
    /// Method to call
    string method;
    /// Arguments to the method, JSON formatted
    string args;
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

/// When creating Message Pipeline
public struct CreatePipeCommand
{
    MessagePipeline pipeline;
}

/// When destructing Message Pipeline
public struct DestroyPipeCommand
{
}

/// Filter out requests before they reach a node
public struct FilterAPI
{
    /// the mangled symbol name of the function to filter
    string func_mangleof;

    /// used for debugging
    string pretty_func;
}

/// Status of a request
public enum Status
{
    /// Request failed
    Failed,

    /// Request timed-out
    Timeout,

    /// Request succeeded
    Success
}

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
}

// very simple & limited variant, to keep it performant.
// should be replaced by a real Variant later
public struct Message
{
    this (Command msg) { this.cmd = msg; this.tag = Message.Type.command; }
    this (Response msg) { this.res = msg; this.tag = Message.Type.response; }
    this (FilterAPI msg) { this.filter = msg; this.tag = Message.Type.filter; }
    this (TimeCommand msg) { this.time = msg; this.tag = Message.Type.time_command; }
    this (ShutdownCommand msg) { this.shutdown = msg; this.tag = Message.Type.shutdown_command; }
    this (CreatePipeCommand msg) { this.create_pipe = msg; this.tag = Message.Type.create_pipe_command; }
    this (DestroyPipeCommand msg) { this.destoy_pipe = msg; this.tag = Message.Type.destoy_pipe_command; }

    union
    {
        Command cmd;
        Response res;
        FilterAPI filter;
        TimeCommand time;
        ShutdownCommand shutdown;
        CreatePipeCommand create_pipe;
        DestroyPipeCommand destoy_pipe;
    }

    ubyte tag;

    /// Status of a request
    enum Type
    {
        command,
        response,
        filter,
        time_command,
        shutdown_command,
        create_pipe_command,
        destoy_pipe_command
    }
}


public alias OnCloseHandler = scope void delegate
    (MessagePipeline pipeline) @safe nothrow;

shared struct AtomicLock
{
    void lock() { while (!cas(&locked, false, true)) { Thread.yield(); } }
    void unlock() { atomicStore!(MemoryOrder.rel)(locked, false); }
    bool locked;
}
/*******************************************************************************

    It has two channels.
    The commuter receives the request, and the provider receives the response.
    The node uses the synthesizer, and the provider is used by the client.

    It has the ability to connect and close pipelines.
    When the pipeline is connected, a new task is added to the scheduler
    on the node.

*******************************************************************************/

public class MessagePipeline
{
    /// Channel of Requestor
    public MessageChannel producer;

    /// Channel of Responsor
    public MessageChannel consumer;

    /// Original Channel of Responsor
    private MessageChannel root_chan;

    /// Name, This is automatically generated by the ID of the thread.
    public string name;

    /// closed
    private bool closed;

    /// This value is true if another request is already in progress.
    private bool busy;

    /// Handler of on close
    private OnCloseHandler onclose;

    private bool closing_soon;

    private AtomicLock alock;

    /***********************************************************************

        Creator

        Params:
            root_chan = Original Channel of Responsor

    ***********************************************************************/

    public this (MessageChannel root_chan, OnCloseHandler onclose = null)
    {
        this (root_chan, new MessageChannel(256), new MessageChannel(256), onclose);
    }


    /***********************************************************************

        Creator

        Params:
            root_chan = Original Channel of Responsor
            producer = Channel of Requestor
            consumer = Channel of Responsor

    ***********************************************************************/

    public this (MessageChannel root_chan, MessageChannel producer, MessageChannel consumer, OnCloseHandler onclose = null)
    {
        this.producer = producer;
        this.consumer = consumer;

        this.closed = true;
        this.busy = false;
        this.closing_soon = true;
        this.root_chan = root_chan;
        this.onclose = onclose;

        this.name = format("%x", thisThreadID);
    }


    /***********************************************************************

        Connect the pipeline.

    ***********************************************************************/

    public void open ()
    {
        alock.lock();
        scope (exit) alock.unlock();

        this.root_chan.send(Message(CreatePipeCommand(this)));
        this.closed = false;
    }


    /***********************************************************************

        Disconnect the pipeline.

    ***********************************************************************/

    public void close ()
    {
        alock.lock();
        scope (exit) alock.unlock();

        this.consumer.send(Message(DestroyPipeCommand()));
        this.closed = true;

        if (this.onclose)
            this.onclose(this);
    }


    /***********************************************************************

        Request a response to the message through the pipeline.

        Params:
            req = request message
            timeout = any timeout to use

        Return:
            msg = value to receive

    ***********************************************************************/

    public Message query (Message req, Duration timeout = Duration.init)
    {
        if (this.closed)
            assert(0, "MessagePipeline is closed.");

        this.busy = true;
        scope (exit)
            this.busy = false;

        this.consumer.send(req);

        Message msg;
        auto limit = MonoTime.currTime + timeout;

        while (true)
        {
            if (this.producer.tryReceive(&msg))
            {
                if ((msg.tag == Message.Type.response) && (req.cmd.id == msg.res.id))
                    return msg;
            }

            if (timeout != Duration.init)
            {
                auto left = limit - MonoTime.currTime;
                if (left.isNegative)
                    return Message(Response(Status.Timeout, req.cmd.id));
            }

            thisScheduler.yield();
        }
    }


    /***********************************************************************

        Send a response message through the pipeline.

        Params:
            res = response message

    ***********************************************************************/

    public void reply (Message res)
    {
        if (this.closed)
            assert(0, "MessagePipeline is closed.");

        this.producer.send(res);
    }


    /***************************************************************************

        Return closing status.

        Return:
            true if the message pipeline is closed, otherwise false.

    ***************************************************************************/

    public @property bool isClosed () @safe @nogc pure
    {
        return this.closed;
    }


    /***************************************************************************

        Return busy status.

        Return:
            true if the message pipeline is busy, otherwise false.

    ***************************************************************************/

    public @property bool isBusy () @safe @nogc pure
    {
        return this.busy;
    }


    public @property void isClosingSoon (bool value) @safe @nogc pure
    {
        alock.lock();
        scope (exit) alock.unlock();

        this.closing_soon = value;
    }

    public @property bool isClosingSoon () @safe @nogc pure
    {
        alock.lock();
        scope (exit) alock.unlock();

        return this.closing_soon;
    }

    /***************************************************************************

        Get the next available request ID.

        Returns:
            request ID.

    ***************************************************************************/

    public size_t getId () @safe nothrow
    {
        static size_t last_idx;
        return last_idx++;
    }
}


/*******************************************************************************

    This registry allows to look up a `MessagePipeline` based on a `ThreadID`.

*******************************************************************************/

public shared struct MessagePipelineRegistry
{
    static shared struct RegistryLock
    {
        void lock() { while (!cas(&locked, false, true)) { Thread.yield(); } }
        void unlock() { atomicStore!(MemoryOrder.rel)(locked, false); }
        bool locked;
    }
    static shared RegistryLock registry_lock;

    private MessagePipeline[string] pipelines;


    /***************************************************************************

        Gets the MessageChannel associated with name.

        Params:
            name = The name to locate within the registry.

        Returns:
            The associated MessagePipeline or null
            if name is not registered.

    ***************************************************************************/

    MessagePipeline locate (string name)
    {
        registry_lock.lock();
        scope (exit)
            registry_lock.unlock();

        if (shared(MessagePipeline)* p = name in this.pipelines)
            return *cast(MessagePipeline*)p;

        return null;
    }


    /***************************************************************************

        Gets the MessageChannel associated with name.

    ***************************************************************************/

    MessagePipeline locate ()
    {
        auto name = format("%x", thisThreadID);

        return this.locate(name);
    }


    /***************************************************************************

        Register message pipeline.

        Params:
            pipeline = Instanse of MessagePipeline.

    ***************************************************************************/

    bool register (MessagePipeline pipeline)
    {
        registry_lock.lock();
        scope (exit)
            registry_lock.unlock();

        if (pipeline.name in pipelines)
            return false;
        if (pipeline.isClosed)
            return false;

        this.pipelines[pipeline.name] = cast(shared)pipeline;
        return true;
    }


    /***************************************************************************

        Removes  message pipeline

        Params:
            pipeline = Instanse of MessagePipeline

    ***************************************************************************/

    bool unregister (MessagePipeline pipeline)
    {
        registry_lock.lock();
        scope (exit)
            registry_lock.unlock();

        if (shared(MessagePipeline)* p = pipeline.name in this.pipelines)
        {
            this.pipelines.remove(pipeline.name);
            return true;
        }
        return false;
    }
}


/***************************************************************************

    Getter of MessageChannel assigned to a called thread.

    Returns:
        Returns instance of `MessageChannel` that is created by top thread.

***************************************************************************/

public @property MessageChannel thisMessageChannel () nothrow
{
    auto p = "messagechannel" in thisInfo.objects;
    if (p !is null)
        return cast(MessageChannel)*p;
    else
        return null;
}


/***************************************************************************

    Setter of MessageChannel assigned to a called thread.

    Params:
        value = The instance of `MessageChannel`.

***************************************************************************/

public @property void thisMessageChannel (MessageChannel value) nothrow
{
    thisInfo.objects["messagechannel"] = value;
}
