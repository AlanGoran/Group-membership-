-module(gms2).
-export([start/1,start/2,init/3,init/4]).
 
-define(timeout, 500).
-define(arghh, 100).

% First node added to a group 
start(Id) ->
    Rnd = random:uniform(1000),
    Self = self(),
    {ok, spawn_link(fun()-> init(Id, Rnd, Self) end)}.

init(Id, Rnd, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    leader(Id, Master, [], [Master]).


% Adding nodes to a group that already have members
start(Id, Grp) ->
    Rnd = random:uniform(1000),
    Self = self(),
    {ok, spawn_link(fun()-> init(Id, Rnd, Grp, Self) end)}.

init(Id, Rnd, Grp, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    Self = self(),
    Grp ! {join, Master, Self},
    receive
    {view, [Leader|Slaves], Group} ->
        erlang:monitor(process, Leader), % detects that a leader has died and will move to an election state (sends 'DOWN')
        Master ! {view, Group},
        slave(Id, Master, Leader, Slaves, Group)
    after ?timeout -> %Since the leader can crash it could be that a node that wants to join the group will never receive a reply. The message could be forwarded to a dead leader and the joining node is never informed of the fact that its request was lost. We simply add a timeout when waiting for an invitation to join the group.
        Master ! {error, "no reply from leader"}
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
    {'DOWN', _Ref, process, Leader, _Reason} ->
        election(Id, Master, Slaves, Group);
    stop ->
        ok
    end.


% will send a message to each of the processes in a list.
bcast(Id, Msg, Nodes) ->
    lists:foreach(fun(Node) -> Node ! Msg, crash(Id) end, Nodes).

% We define a constant arghh that defines the risk of crashing. A value of 100 means that a process will crash in average once in a hundred attempts.
crash(Id) ->
    case random:uniform(?arghh) of
        ?arghh ->
            io:format("leader ~w: crash~n", [Id]),
            exit(no_luck);
		_ -> 
			ok
	end.


% the process will select the first node in its lists of peers and elect this as the leader. 
election(Id, Master, Slaves, [_|Group]) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            bcast(Id, {view, Slaves, Group}, Rest),
            Master ! {view, Group},
            io:format("New Leader: ~w ~n", [Id]),
            leader(Id, Master, Rest, Group);
        [Leader|Rest] ->
            erlang:monitor(process, Leader),
            io:format("Still Slaves: ~w ~n", [Id]),
            slave(Id, Master, Leader, Rest, Group)
	end.


