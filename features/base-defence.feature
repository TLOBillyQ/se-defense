# mutation-stamp: sha256=03a28a7db1979fd9c8634d0794ae30f1988c756edd769729e3e7e83a695e4fa2
# acceptance-mutation-manifest-begin
# {"version":1,"tested_at":"2026-09-05T03:17:15.557158Z","feature_name":"Base Defence headless game flow","feature_path":"features/base-defence.feature","background_hash":"4a2aa6b9ca0c91b3739c51c9d223601663d76d460b7105ff05d029d92e6a0974","implementation_hash":"sha256:aabdd8c6853ae1d6af3a7b8bb3ca060fe50d85470be7cd5ab906e50a4b9cccd1","scenarios":[{"index":1,"name":"building placement costs its price","scenario_hash":"0e16c13aa7889223c33b434e8b670f3b038c126c40beeae013ad54528bf5ac12","mutation_count":10,"result":{"Total":10,"Killed":10,"Survived":0,"Errors":0},"tested_at":"2026-09-05T03:16:57.393973Z"}]}
# acceptance-mutation-manifest-end

Feature: Base Defence headless game flow

  Background:
    Given a fresh headless game
    And the client is ready

  Scenario: pregame rejects placement until auto start
    Given the game is in Pregame mode
    When the client sends a place intent for turret
    Then no building is being placed
    When the game advances 100 ticks
    Then the game is in Playing mode
    And the money is 100

  Scenario Outline: building placement costs its price
    When the game advances 100 ticks
    Then the game is in Playing mode
    When the client sends a place intent for <building>
    And the client taps the board at <x> <z>
    And the game advances 4 ticks
    Then the <building> count on the board is <count>
    And the money decreased by <cost>

    Examples:
      | building | x | z | count | cost |
      | turret   | 3 | 0 | 1     | 100  |
      | relay    | 0 | 3 | 1     | 50   |

  Scenario: relay extends the power grid beyond the core
    When the game advances 100 ticks
    Then the game is in Playing mode
    When the gm sets the money to 1000
    And the client sends a place intent for relay
    And the client taps the board at 0 3
    And the game advances 10 ticks
    Then the relay count on the board is 1
    And the relay has power
    When the client sends a place intent for radar
    And the client taps the board at 0 6
    And the game advances 10 ticks
    Then the radar count on the board is 1
    And the radar has power

  Scenario: mining out all resources reaches victory and restart rebuilds the game
    When the game advances 100 ticks
    Then the game is in Playing mode
    When the gm mines out all resources
    And the game advances 3 ticks
    Then the game is in Victory mode
    And the victory banner is visible
    When the client restarts the game
    And the game advances 1 tick
    Then the game is in Pregame mode
    And the entity count on the board is 7

  Scenario: destroying the core reaches game over
    When the game advances 100 ticks
    Then the game is in Playing mode
    When the gm destroys the core
    And the game advances 3 ticks
    Then the game is in GameOver mode
    And the gameover banner is visible
