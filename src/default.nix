let
  utils = import ./lib.nix;
  perform = import ./collect.nix;
  inherit (utils) inModuleEval;

  # Makes imp callable: imp ./path or imp { config, ... }
  functor = self: arg: perform self.__config (if inModuleEval arg then [ ] else arg);

  # The imp builder object - a stateful configuration that produces the API
  callable =
    let
      # Initial configuration state
      initial = {
        api = { };
        mapf = (i: i);
        treef = import;
        filterf = _: true;
        paths = [ ];

        # State functor: receives update function, returns new state with bound API
        __functor =
          config: update:
          let
            updated = update config;
            current = config update;
            boundAPI = builtins.mapAttrs (_: g: g current) updated.api;

            # Import API methods with current state
            apiMethods = import ./api.nix {
              inherit
                config
                update
                updated
                current
                callable
                ;
            };
          in
          boundAPI
          // apiMethods
          // {
            __config = updated;
            __functor = functor;
          };
      };
    in
    initial (config: config);

in
callable
