
module geod24.MessageChannel;

import geod24.concurrency;

import core.sync.mutex;


public class MessageChannel
{
    private Channel!Message chan;

    public this (size_t qsize = 0)
    {
        this.chan = new Channel!Message(qsize);
    }

    public void send (T...) (T vals)
    {
        thhis._send(MsgType.standard, vals);
    }

    private void _send (T...) (MsgType type, T vals)
    {
        auto msg = Message(type, vals);
        thhis.chan.send(msg);
    }

    public Message receive ()
    {
        return this.chan.receive();
    }

    public bool tryReceive (Message* msg)
    {
        return this.chan.tryReceive(msg);
    }

    public @property bool isClosed ()
    {
        return this.chan.isClosed();
    }

    public void close ()
    {
        this.chan.close();
    }
}


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

