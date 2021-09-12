
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity rll27_gaps_to_bits is
  port (
    clock40mhz : in std_logic;

    -- Quantised gaps as input
    gap_valid : in std_logic := '0';
    gap_size : in unsigned(2 downto 0);

    -- Output bits as we decode them
    bit_valid : out std_logic := '0';
    bit_out : out std_logic := '0';

    -- Indicate when we have detected a sync byte
    sync_out : out std_logic := '0'
    
    );
end rll27_gaps_to_bits;

architecture behavioural of rll27_gaps_to_bits is

  signal last_bit : std_logic := '0';

  signal check_sync : std_logic := '0';
  
  -- Used for detecting sync bytes
  signal recent_gaps : unsigned(8 downto 0) := (others => '0');
  -- Sync byte is gaps of 7 2 2 = 111 010 010
  constant sync_gaps : unsigned(8 downto 0) := "111010101";

  signal bit_queue : std_logic_vector(1 downto 0) := "00";
  signal bits_queued : integer range 0 to 2 := 0;

  signal last_gap_valid : std_logic := '0';
  
begin

  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      last_gap_valid <= gap_valid;
      if gap_valid = '1' and last_gap_valid='0' then
--        report "Interval of %" & to_string(std_logic_vector(gap_size));
        
        -- Detect sync byte
        recent_gaps(8 downto 3) <= recent_gaps(5 downto 0);
        recent_gaps(2 downto 0) <= gap_size;
        check_sync <= '1';

        -- Process gap to produce bits

      else
        check_sync <= '0';
      end if;

      -- Output bits or sync
      if (check_sync='1') and (recent_gaps = sync_gaps) then
        -- Output sync mark
        sync_out <= '1';
        bits_queued <= 0;
        bit_valid <= '0';
        last_bit <= '1';  -- because sync marks are $A1
      elsif bits_queued /= 0 then
        -- Output queued bit
        bit_valid <= '1';
        bit_out <= bit_queue(1);
        last_bit <= bit_queue(1);
        bit_queue(1) <= bit_queue(0);
        bits_queued <= bits_queued -1;
      else
        sync_out <= '0';
        bit_valid <= '0';
      end if;
      
    end if;    
  end process;
end behavioural;

