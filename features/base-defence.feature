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
