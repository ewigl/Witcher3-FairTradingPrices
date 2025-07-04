class FairTradingPrices {
  // === CONFIG VARIABLE NAMES ===
  // These correspond to identifiers used in the mod menu XML.
  // They are used to read and write user preferences from config.
  var CFG_GROUP_NAME: name;
  var CFG_FTP_IsEnabled: name;
  var CFG_FTP_SellModifier: name;
  var CFG_FTP_OriginalPrices: name;
  var CFG_FTP_PriceMultiplier: name;
  var CFG_FTP_InfiniteFundsShops: name;

  // === CORE REFERENCES ===
  var config: CInGameConfigWrapper;
  var dm: CDefinitionsManagerAccessor;

  // === ITEM PRICE DATA ===
  var itemName: name;
  var baseItemPrice: int; // Static base item price from game definitions
  var dynamicItemPrice: int; // In-game modified price (durability, level, etc.)
  var calcItemPrice: int; // Price used for calculations depending on mod settings
  var finalItemPrice: int; // Final computed price returned to caller

  // === CONFIG VALUE CACHE ===
  var FTPOriginalPrices: bool;
  var FTPSellModifier: float;
  var FTPPriceMultiplier: float;

  /**
   * Entry point for mod logic.
   * Ensures the configuration is initialized and a default preset is applied
   * on the first game launch or when settings are missing.
   */
  function Init() {
    PrepareConfigVariables();
    // Applies "Fair Trade" preset
    if (GetCfgValue(CFG_FTP_IsEnabled) == "") {
      config.ApplyGroupPreset(CFG_GROUP_NAME, 1);
      theGame.SaveUserSettings();
    }
  }

  /**
   * Initializes variable names used to access mod config values.
   * Must be called before reading from or writing to the configuration.
   */
  function PrepareConfigVariables() {
    CFG_GROUP_NAME = 'ModFairTradingPrices';
    CFG_FTP_IsEnabled = 'FTP_IsEnabled';
    CFG_FTP_SellModifier = 'FTP_SellModifier';
    CFG_FTP_OriginalPrices = 'FTP_OriginalPrices';
    CFG_FTP_PriceMultiplier = 'FTP_PriceMultiplier';
    CFG_FTP_InfiniteFundsShops = 'FTP_InfiniteFundsShops';

    config = theGame.GetInGameConfigWrapper();
  }

  /**
   * Retrieves a configuration value as a string from the mod config group.
   *
   * @param varId - The variable's ID in the XML config (e.g., 'FTPSellModifier').
   * @return The value as a string. Returns "" if not found or invalid.
   */
  function GetCfgValue(varId: name): string {
    return config.GetVarValue(CFG_GROUP_NAME, varId);
  }

  /**
   * Retrieves a configuration value and converts it to an int.
   *
   * @param varId - The int variable's ID in the config.
   * @return The int value. Defaults to 0 if conversion fails or is invalid.
   */
  function GetCfgInt(varId: name): int {
    return StringToInt(GetCfgValue(varId));
  }

  /**
   * Retrieves a configuration value and converts it to an float.
   *
   * @param varId - The int variable's ID in the config.
   * @return The float value. Defaults to 0.0 if conversion fails or is invalid.
   */
  function GetCfgFloat(varId: name): float {
    return StringToFloat(GetCfgValue(varId));
  }

  /**
   * Converts a floating-point number to the nearest integer using standard rounding.
   *
   * @param floatValue - The float value to round.
   * @return int - The value rounded to the nearest integer.
   */
  function FloatToInt(floatValue: float): int {
    return (int)(floatValue + 0.5);
  }

  /**
   * Converts a percentage value to a decimal fraction for scaling purposes.
   *
   * @param floatValue - A numeric percentage value (e.g., 75 for 75%).
   * @return float - The corresponding decimal value (e.g., 0.75).
   */
  function GetPercent(floatValue: float): float {
    return floatValue / 100.0;
  }

  /**
   * Retrieves a configuration value and converts it to a boolean.
   *
   * @param varId - The boolean variable's ID in the config.
   * @return The boolean value. Returns true if the string is exactly "true".
   */
  function GetCfgBool(varId: name): bool {
    return GetCfgValue(varId) == "true";
  }

  /**
   * Checks whether the Fair Trading Prices mod is currently enabled via config.
   *
   * @return True if the mod is enabled in the user settings, false otherwise.
   */
  function IsModEnabled(): bool {
    return GetCfgBool(CFG_FTP_IsEnabled);
  }

  /**
   * Determines whether shops have unlimited funds for buying items.
   *
   * @return True if shops have infinite funds, false otherwise.
   */
  function ShopHasInfiniteFunds(): bool {
    return GetCfgBool(CFG_FTP_InfiniteFundsShops);
  }

  /**
   * Calculates a fair trade price for a specific inventory item, based on mod settings.
   *
   * This function is called whenever the game needs to determine the value of an item,
   * either for selling (player -> merchant) or purchasing (merchant -> player).
   *
   * Logic Summary:
   * - Chooses between base and dynamic prices depending on config.
   * - Applies a global price multiplier.
   * - If selling, applies a sell modifier and ensures minimum return.
   *
   * @param playerInventory - The 'CInventoryComponent' of the player.
   *                          Must consistently be the same player inventory for each interaction.
   *                          Mixing types may lead to inconsistent price behavior.
   * @param item - The specific 'SInventoryItem' instance representing the item in the inventory.
   * @param itemName - The 'name' identifier of the item.
   * @param origItemPrice - The modified item price as reported by the game (affected by durability, level, etc.).
   * @param playerSellingItem - Flag indicating if the player is the seller.
   *                            If true, applies sell modifier.
   *
   * @return int - The final computed price for the item:
   *             - If item price is invalid, returns -1 (item not for sale).
   *             - If player is selling and modifier is active, returns scaled value.
   *             - Always returns at least 1 when selling to avoid 0-gold trades.
   *             - Otherwise, returns the full dynamic price.
   */
  function GetFairItemPrice(playerInventory: CInventoryComponent, item: SInventoryItem, itemName: name, origItemPrice: int, playerSellingItem: bool): int {
    // Get reference to game definitions manager (used for base price lookup)
    dm = theGame.GetDefinitionsManager();

    // Calculate base and dynamic prices
    baseItemPrice = dm.GetItemPrice(itemName);
	dynamicItemPrice = playerInventory.GetInventoryItemPriceModified(item, false); // Sets false to make both player and merchant prices equal for calculation

    // Read mod settings
    FTPOriginalPrices = GetCfgInt(CFG_FTP_OriginalPrices);
    FTPPriceMultiplier = GetCfgFloat(CFG_FTP_PriceMultiplier);
    FTPSellModifier = GetPercent(GetCfgInt(CFG_FTP_SellModifier));

    // Determine which price to use for calculation (based on config)
    if (FTPOriginalPrices) {
      calcItemPrice = FloatToInt(dynamicItemPrice * FTPPriceMultiplier);
    } else {
      calcItemPrice = FloatToInt(baseItemPrice * FTPPriceMultiplier);
    }

    // Handle edge cases (negative prices, non-tradable items)
    // This may indicate that the item is not tradable, or quest related.
    if (calcItemPrice < 0 || origItemPrice < 0) {
      return -1;
    }

    // If the calculated item price is exactly zero, return 0 immediately.
    // This typically indicates that the item is free (e.g. quest item),
    // and should not be tradable for profit.
    if (calcItemPrice == 0) {
      return 0;
    }

    // If the player is selling, apply sell modifier (if configured)
    if (playerSellingItem && FTPSellModifier > 0 && FTPSellModifier < 1.0) {
      finalItemPrice = FloatToInt(calcItemPrice * FTPSellModifier);

      // Ensure minimum return of 1 gold when selling even if the computed value is 0.
      // This prevents cases where low-value items would result in a 0-gold transaction,
      // which could break shop logic or player expectations.
      if (finalItemPrice == 0) {
        finalItemPrice = 1;
      }

      return finalItemPrice;
    }

    // Return unmodified price if the player buying
    return calcItemPrice;
  }
}

// --- MOD SYSTEM HOOKS ---

/**
 * Global singleton instance of FairTradingPrices accessible through W3GameParams.
 * Used to access config and price logic from anywhere in the game.
 */
@addField(W3GameParams)
var m_FTP: FairTradingPrices;

/**
 * Injects mod initialization into W3GameParams.Init().
 * Ensures config is loaded and ready before gameplay begins.
 */
@wrapMethod(W3GameParams)
function Init() {
  wrappedMethod();
  m_FTP = new FairTradingPrices in this;
  m_FTP.Init();
}
