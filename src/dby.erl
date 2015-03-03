-module(dby).

% @doc
% dobby API
% @end

-export([publish/2,
         publish/4,
         search/4,
         subscribe/4,
         unsubscribe/1,
         identifiers/4
        ]).

-include_lib("dobby_clib/include/dobby.hrl").

% =============================================================================
% API functions
% =============================================================================

% @equiv publish([{Endpoint1, Endpoint2, LinkMetadata}], Options).
-spec publish(dby_endpoint(), dby_endpoint(), metadata(), [publish_option()]) -> ok | {error, reason()}.
publish(Endpoint1, Endpoint2, LinkMetadata, Options) ->
    publish([{Endpoint1, Endpoint2, LinkMetadata}], Options).

% @doc
% `publish/2' adds, removes, or modifies an identifier or link,
% or sends a message via an identifier or
% link. The endpoints of the link are specified using an identifier
% or a tuple with the identifier and metadata.  If the endpoint is
% specified as an identifier, the metadata for that identifier is not
% changed.  Likewise, if the metadata is `nochange' the metadata for
% the endpoint is not changed.  If the identifier metadata is `delete' the
% identifier is deleted and all links to the identifier are also deleted.
% If `LinkMetadata' is not specified or
% is `nochange' the link metadata is not changed.  If LinkMetadata is
% `delete' the link between the two endpionts is deleted.
% If `publish/2' creates
% a new identifier or link and no metadata is provided, the metadata
% is set to `null'.  `Metadata' may be any Erlang term that can be
% represented as a JSON.  If the metadata is specified as a function,
% the function is called with the old metadata and returns the updated
% metadata for that link or identifier.  The `persistent' option means
% metadata changes are persisted in Dobby.  The `message' option means
% metadata changes are communicated to subscriptions but the changes
% are not persisted in dobby.  `message' is the default behavior. For
% a `message' publish, the two endpoints and link must already exist.
%
% Returns `badarg' for `message' publish if one of the endppoints or the
% link between them does not exist.
%
% `publish/2' may also be called with an endpoint.  This is a convenience
% for adding, removing, or modifying a single identifier.
% @end
-spec publish([dby_endpoint() | link()] | dby_endpoint(), [publish_option()]) -> ok | {error, reason()}.
publish(Endpoint, Options) when is_tuple(Endpoint); is_binary(Endpoint) ->
    publish([Endpoint], Options);
publish(Data, Options) ->
    call(dby_publish, [Data, Options]).

% @doc
% `search/4' performs a fold over the graph beginning with the identifier
% in `StartIdentifier'. The options `breadth' and `depth' control how the
% graph is traversed.  For `breadth', all the links to 'StartIdentifier'
% are traversed first, followed by all the links of the 'StartIdentifier'
% neighbors, etc.  For `depth', one link of `StartIdentifier' is traversed,
% followed by one link of that neighbor identifier, etc.  If neither
% is specified, `breadth' is used.  `Acc' is the initial accumulator
% value.  `Fun' is called for every identifier traversed by search. It
% controls the graph traversal and may also transform the result.
% `Identifier' is the current identifier. `IdMetadata' is the metadata
% for the identifier. `Path' is the list of identifiers with their
% metadata and link metadata that is the path from `StartIdentifier'
% to `Identifier'. `Acc0' is the current accumulator. The first identifier
% in the `Path' list is immediate neighbor of `Identifier' that lead to
% `Identifier'. `Fun' returns a status that controls the next step of the
% navigation and the new accumulator.  The possible control values
% are: `continue' to continue the search, `skip' to continue the search
% but skip navigating to any neighbors of this identifier, `stop' to
% stop the search with this identifier.
% 
% The option `max_depth' controls how far
% to navigate away from the starting identifier.  `max_depth' of 0 means
% no navigation is performed.  `max_depth' of one means search only
% navigates to the immediate neighbors of the starting identifier.
% If `max_depth' is not provided, `0' is used.
%
% The `loop' option specifies the loop detection algorithm.  `none' means
% there is no loop detection and `Fun' may see the same identifier
% more than once.  `link' means that a link is traversed only once, but
% if there is more than one link to an identifier, `Fun' may see
% the same identifier more than once.  `identifier' means that an
% identifier is traversed only once, so `Fun' will never see the
% same identifier more than once.  If `loop' is not provided, `identifier'
% loop detection is used.
% @end
-spec search(Fun :: search_fun(), Acc :: term(), StartIdentifier :: dby_identifier(), [search_options()]) -> term() | {error, reason()}.
search(Fun, Acc, StartIdentifier, Options) ->
    call(dby_search, [Fun, Acc, StartIdentifier, Options]).

% @doc
% `subscribe/4' creates a subscription and when successful returns a
% subscription id. A subscription is a standing search and many of
% the parameters for subscribe are the same as they are for search.
% A subscription may be on publishing of persistent data or messages,
% or both.  The subscription may provide a delta function, `DFun', that
% computes the delta from previous search `Acc' to the new search `Acc'.
% This function is only called `LastAcc' and `NewAcc' are different.  `DFun'
% returns the computed `Delta', 'stop' to delete the subscription and no
% further processing is performed on this subscription, or `nodelta'
% to indicate that there was no delta.  If no `DFun' is not provided
% in the options, Dobby uses `NewAcc' as the delta.  The subscription
% may provide a delivery function `SFun'.  `SFun' is only called if there
% is a delta in the subscription’s search result, that is, if `DFun' returns
% a delta.
% If `DFun' returns a delta, the `SFun' is called
% with the delta.  If `DFun' returns nodelta, `SFun' is not called.  If
% no `DFun' is provided, `SFun' is called with NewAcc.  `SFun' may return
% `stop' to delete the subscription, otherwise it should return `ok'.  If
% no `SFun' is provided, no deltas are delivered.
% @end
-spec subscribe(Fun :: search_fun(), Acc :: term(), StartIdentifier :: dby_identifier(), [subscribe_options()]) -> {ok, subscription_id()} | {error, reason()}.
subscribe(Fun, Acc, StartIdentifier, Options) ->
    call(dby_subscribe, [Fun, Acc, StartIdentifier, Options]).

% @doc
% `unsubscribe/1' deletes a subscription.  Attempts to delete an invalid
% or already deleted subscription are ignored.
% @end
-spec unsubscribe(subscription_id()) -> ok.
unsubscribe(SubscriptionId) ->
    call(dby_unsubscribe, SubscriptionId).

% @doc
% When used as the function for `dby:search/4', returns the list of
% identifiers traversed in the search as tuples containing the
% identifier, the identifier's metadata, and the link's metadata.
% @end
-spec identifiers(dby_identifier(), jsonable(), jsonable(), list()) -> {continue, list()}.
identifiers(Identifier, IdMetadata, LinkMetadata, Acc) ->
    {continue, [{Identifier, IdMetadata, LinkMetadata} | Acc]}.

% =============================================================================
% Local functions
% =============================================================================

% call the dobby server
call(Op, Args) ->
    gen_server:call({global, dobby}, {Op, Args}).
