-module(gms1).
-export([start/1,start/2,init/2,init/3]).
 
% First node added to a group 
start(Id) ->
    Self = self(),
    {ok, spawn_link(fun()-> init(Id, Self) end)}.

% Adding nodes to a group that already have members
start(Id, Grp) ->
    Self = self(),
    {ok, spawn_link(fun()-> init(Id, Grp, Self) end)}.
 
 
init(Id, Master) ->
    leader(Id, Master, [], [Master]).
 
init(Id, Grp, Master) ->
    Self = self(),
    Grp ! {join, Master, Self},
    receive
    {view, [Leader|Slaves], Group} ->
        Master ! {view, Group},
        slave(Id, Master, Leader, Slaves, Group)
    end.

leader(Id, Master, Slaves, Group) ->
    receive
    % handle a message either from its own master or from a peer node. A message {msg, Msg} is multicasted to all peers and a message Msg is sent to the application layer.
    {mcast, Msg} ->
        bcast(Id, {msg, Msg}, Slaves),
        Master ! Msg,
        leader(Id, Master, Slaves, Group);

    % handle a message, from a peer or the master, that is a request from a node to join the group. The message contains both the process identifier of the application layer, Wrk, and the process identifier of its group process.
    {join, Wrk, Peer} ->
        Slaves2 = lists:append(Slaves, [Peer]),
        Group2 = lists:append(Group, [Wrk]),
        bcast(Id, {view, [self()|Slaves2], Group2}, Slaves2),
        Master ! {view, Group2},
        leader(Id, Master, Slaves2, Group2);

    stop ->
        ok
    end.
 

slave(Id, Master, Leader, Slaves, Group) ->
    receive
    % a request from its master to multicast a message, the message is forwarded to the leader.
    {mcast, Msg} ->
        Leader ! {mcast, Msg},
        slave(Id, Master, Leader, Slaves, Group);
    % a request from the master to allow a new node to join the group, the message is forwarded to the leader.
    {join, Wrk, Peer} ->
        Leader ! {join, Wrk, Peer},
        slave(Id, Master, Leader, Slaves, Group);
    %  a multicasted message from the leader. A message Msg is sent to the master.
    {msg, Msg} ->
        Master ! Msg,
        slave(Id, Master, Leader, Slaves, Group);
    % a multicasted view from the leader. A view is delivered to the master process.
    {view, [Leader|Slaves2], Group2} ->
        Master ! {view, Group2},
        slave(Id, Master, Leader, Slaves2, Group2);
    stop ->
        ok
    end.


% will send a message to each of the processes in a list.
bcast(Id, Msg, Nodes) ->
    lists:foreach(fun(Node) -> Node ! Msg end, Nodes).



