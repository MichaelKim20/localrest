
module geod24.MessageChannel;

import geod24.concurrency;

import core.sync.mutex;
import core.thread;
import core.time;

import std.traits;

alias MessageChannel = Channel!Message;

version (unittest):

/// Data sent by the caller
private struct Command
{
    MessageChannel sender;
    size_t id = size_t.max;
    string method;
    string args;
}
/// Status of a request
private enum Status
{
    Failed,
    Timeout,
    Success
}
/// Data sent by the callee back to the caller
private struct Response
{
    Status status;
    size_t id;
    string data;
}

/// Ask the node to exhibit a certain behavior for a given time
private struct TimeCommand
{
    /// For how long our remote node apply this behavior
    Duration dur;
    /// Whether or not affected messages should be dropped
    bool drop = false;
}

private struct Shutdown
{
}

// Thread Creation

private template isSpawnable(F, T...)
{
    template isParamsImplicitlyConvertible(F1, F2, int i = 0)
    {
        alias param1 = Parameters!F1;
        alias param2 = Parameters!F2;
        static if (param1.length != param2.length)
            enum isParamsImplicitlyConvertible = false;
        else static if (param1.length == i)
            enum isParamsImplicitlyConvertible = true;
        else static if (isImplicitlyConvertible!(param2[i], param1[i]))
            enum isParamsImplicitlyConvertible = isParamsImplicitlyConvertible!(F1,
                    F2, i + 1);
        else
            enum isParamsImplicitlyConvertible = false;
    }

    enum isSpawnable = isCallable!F && is(ReturnType!F == void)
            && (isParamsImplicitlyConvertible!(F, void function(Tid, T))
            || isParamsImplicitlyConvertible!(F, void function(MessageChannel, T)))
            && (isFunctionPointer!F || !hasUnsharedAliasing!F);
}

bool hasLocalAliasing(Types...)()
{
    import std.typecons : Rebindable;

    // Works around "statement is not reachable"
    bool doesIt = false;
    static foreach (T; Types)
    {
        static if (is(T == Tid))
        { /* Allowed */ }
        else static if (is(T == MessageChannel))
        { /* Allowed */ }
        else static if (is(T : Rebindable!R, R))
            doesIt |= hasLocalAliasing!R;
        else static if (is(T == struct))
            doesIt |= hasLocalAliasing!(typeof(T.tupleof));
        else
            doesIt |= std.traits.hasUnsharedAliasing!(T);
    }
    return doesIt;
}

Message toMessage (T) (T data)
{
    return Message(MsgType.standard, data);
}

/// spawn thread
MessageChannel spawnThread (F, T...)(F fn, T args)
if (isSpawnable!(F, T))
{
    static assert(!hasLocalAliasing!(T), "Aliases to mutable thread-local data not allowed.");

    auto spawnChannel = new MessageChannel(256);

    void exec()
    {
        thisScheduler = new FiberScheduler();
        fn(spawnChannel, args);
    }

    auto t = new InfoThread(&exec);
    t.start();

    return spawnChannel;
}

void shutdown (MessageChannel chan)
{
    chan.send(Message(MsgType.standard, Shutdown()));
}

unittest
{
    import std.conv;

    static void spawned (MessageChannel self)
    {
        scope scheduler = thisScheduler;
        scope channel = self;
        bool terminate = false;

        scheduler.start({
            while (!terminate)
            {
                Message msg = channel.receive();
                if (msg.convertsTo!(Command))
                {
                    auto cmd = msg.data.peek!(Command);
                    if (cmd.method == "pow")
                    {
                        immutable int value = to!int(cmd.args);
                        auto msg_res = toMessage(Response(Status.Success, 0, to!string(value * value)));
                        cmd.sender.send(msg_res);
                    }
                    else
                    {
                        assert(0, "Unmatched method name: " ~ cmd.method);
                    }
                }
                else if (msg.convertsTo!(Shutdown))
                {
                    terminate = true;
                }
                else
                {
                    assert(0, "Unexpected type");
                }
            }
        });
    }

    auto node = spawnThread(&spawned);

    auto client = new MessageChannel(256);
    auto msg_cmd = toMessage(Command(client, 0, "pow", "2"));
    node.send(msg_cmd);

    auto res_msg = client.receive();
    auto res = res_msg.data.peek!(Response);
    assert(res.data == "4");

    shutdown(node);
}

unittest
{
    import std.conv;

    static void handleCommand (Command cmd)
    {
        if (cmd.method == "pow")
        {
            immutable int value = to!int(cmd.args);
            auto msg_res = toMessage(Response(Status.Success, 0, to!string(value * value)));
            cmd.sender.send(msg_res);
        }
    }

    static void spawned (MessageChannel self)
    {
        import std.datetime.systime : Clock, SysTime;
        import std.algorithm : each;
        import std.range;

        // used for controling filtering / sleep
        struct Control
        {
            SysTime sleep_until;     // sleep until this time
            bool drop;               // drop messages if sleeping
            bool send_response_msg;  // send drop message
        }
        scope scheduler = thisScheduler;
        scope channel = self;

        Control control;
        bool terminate = false;
        Command[] await_msg;

        bool isSleeping ()
        {
            return control.sleep_until != SysTime.init
                && Clock.currTime < control.sleep_until;
        }

        void handleCmd (Command cmd)
        {
            scheduler.spawn({
                handleCommand(cmd);
            });
        }

        scheduler.start({
            while (!terminate)
            {
                Message msg = channel.receive();
                if (msg.convertsTo!(Command))
                {
                    auto cmd = msg.data.peek!(Command);
                    if (!isSleeping())
                        handleCmd(*cmd);
                    else if (!control.drop)
                        await_msg ~= *cmd;
                }
                else if (msg.convertsTo!(TimeCommand))
                {
                    auto time = msg.data.peek!(TimeCommand);
                    control.sleep_until = Clock.currTime + time.dur;
                    control.drop = time.drop;
                }
                else if (msg.convertsTo!(Shutdown))
                {
                    terminate = true;
                }
                else
                {
                    assert(0, "Unexpected type");
                }

                scheduler.yield();

                if (!isSleeping())
                {
                    if (await_msg.length > 0)
                    {
                        await_msg.each!((cmd) => handleCmd(cmd));
                        await_msg.length = 0;
                        assumeSafeAppend(await_msg);
                    }
                }

                scheduler.yield();
            }
        });
    }

    auto node = spawnThread(&spawned);

    auto client = new MessageChannel(256);
    auto msg_cmd = toMessage(Command(client, 0, "pow", "2"));
    node.send(msg_cmd);

    auto res_msg = client.receive();
    auto res = res_msg.data.peek!(Response);
    assert(res.data == "4");

    shutdown(node);
}
