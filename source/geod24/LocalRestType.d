module geod24.LocalRestType;

import geod24.concurrency;
import core.time;

public alias MessageChannel = Channel!Message;


/// Data sent by the caller
public struct Command
{
    /// MessageChannel of the sender thread
    MessageChannel sender;
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

/// very simple & limited variant, to keep it performant.
/// should be replaced by a real Variant later
public struct Message
{
    this (Command msg) { this.cmd = msg; this.tag = Message.Type.command; }
    this (Response msg) { this.res = msg; this.tag = Message.Type.response; }
    this (FilterAPI msg) { this.filter = msg; this.tag = Message.Type.filter; }
    this (TimeCommand msg) { this.time = msg; this.tag = Message.Type.time_command; }
    this (ShutdownCommand msg) { this.shutdown = msg; this.tag = Message.Type.shutdown_command; }

    union
    {
        Command cmd;
        Response res;
        FilterAPI filter;
        TimeCommand time;
        ShutdownCommand shutdown;
    }

    ubyte tag;

    /// Status of a request
    enum Type
    {
        command,
        response,
        filter,
        time_command,
        shutdown_command
    }
}
