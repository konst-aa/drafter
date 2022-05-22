defmodule Drafter.Pod.Server.State do
  alias Drafter.Structs.Player

  defstruct [:status, :set, :option, :group, :loader_name, :player_map, :conditions]

  @type pod_name :: atom()
  @type pod_string :: String.t()

  @type set :: String.t()
  @type option :: String.t()
  @type channelID :: Nostrum.Struct.Channel.id()
  @type pod_pid :: pid()
  @type loader_name :: atom()
  @type direction :: :left | :right

  @typep pack_number :: integer()
  @typep conditions :: %{direction: direction(), pack_number: pack_number()}
  @typep waiting_group :: %{Player.playerID() => boolean()}

  @typep waiting_state :: %__MODULE__{
           status: :waiting,
           set: set(),
           option: option(),
           group: waiting_group()
         }

  @typep running_state :: %__MODULE__{
           status: :running,
           option: option(),
           loader_name: loader_name(),
           player_map: Player.player_map(),
           conditions: conditions()
         }

  @type t :: running_state() | waiting_state()
end
