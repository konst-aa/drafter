# drafter

This is a simple bot that organizes magic the gathering drafts.

## Installation

Drafter depends on [ImageMagick](https://imagemagick.org/script/download.php) for concatenating card images.
If you have brew installed, you can get it with:

```shell
brew install imagemagick
```

Once that is out of the way:

```shell
git clone git@github.com:konstantin-aa/drafter-ex.git
cd drafter-ex
mix deps.get
```

## Configuration

The config file can be found in `/config/config.exs`

#### Bot Token

Make sure that your bot has all gateway intents, then paste your bot token into the config file.

#### Super Users

Give people permission to manage pods and sets by adding them to the list of super users.

Example:

```elixir
config :drafter,
  super_users: ["CrystalPal#5751", "Accorata#0236"]
```

#### Prefix

The default prefix is ~!.
Command prefixes have to be set manually because pattern matching in elixir must be done with known binaries.
You can find the dispatcher for all the commands in `/lib/drafter/handler/consumer.ex`.

## Running

In the project directory:

```shell
mix run --no-halt
```

## Set XML

An example xml could be found at `/test/mock-files/minihellscube.xml`

## Commands

Note that set-name doesn't contain the `.json` extension.

### Super User Commands

#### ~!save set-name

Saves attached xml as json in sets/set-name.json

#### ~!delete set-name

Deletes file in sets/set-name.json

#### ~!killall

Kills all pods.

#### ~!kill pod-name

Kills pod named pod-name.

### Regular Commands

#### ~!list

Prints out all the names of saved sets.

#### ~!draft set option group

Will attempt to load the set once all players ready up.

Option: currently the only supported option is "cube". All cards are singleton, 15 cards per pack.
Group: pings to players participating in the pod separated by spaces.
Seating order is in the order of the group, and wraps around. 
(The player to the left of the first player is the last player and vice versa).
Passing starts to the right, then flips after each pack.

Example:

```
~!draft hlc cube @CrystalPal#5751 @Accorata#0236
```

#### ~!ready

Readies you up if you're in a pod.

#### ~!pick index

INDEX IS 0 INDEXED!
Picks the card at index in your current pack.
The top left card in a pack is the 0th card in the pack. The bottom right card is the last.

#### ~!picks

DMs an image of your current picks

### Maintenance Commands

#### ~!ping

We all know what this does

#### ~!prune

Unassigns players from dead pods

#### ~!help

Sends a link to the commands section of the readme.

## Next steps:

More options, cleaner code. Also, I'm planning on contributing to [Temp](https://github.com/danhper/elixir-temp) to automatically clean up directories.
