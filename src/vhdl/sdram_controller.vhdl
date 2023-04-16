library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

------------------------------------------------------------------------------------------------
-- PGS 12MAR2023:
-- NOTE: The cache must remain enabled for writes to be reliable across all
-- MEGA65 board revisions.  This is because the revD HyperRAM chip found on
-- _some_ machines in _some_ batches requires 32-bit writes (but still can be
-- byte masked), for the writes to happen correctly.
-- See https://github.com/MJoergen/HyperRAM/issues/2 for more information.
------------------------------------------------------------------------------------------------


entity sdram_controller is
  generic ( in_simulation : in boolean := false);
  Port ( pixelclock : in STD_LOGIC; -- For slow devices bus interface is
         -- actually on pixelclock to reduce latencies
         -- Also pixelclock is the natural clock speed we apply to the HyperRAM.
         clock162 : in std_logic; -- Used for fast clock for HyperRAM

         -- Option to ignore 100usec initialisation sequence for SDRAM (to
         -- speed up simulation)
         enforce_100us_delay : in boolean := true;
         
         -- Simple counter for number of requests received
         request_counter : out std_logic := '0';
         
         read_request : in std_logic;
         write_request : in std_logic;
         address : in unsigned(26 downto 0);
         wdata : in unsigned(7 downto 0);

         -- Optional 16-bit interface (for Amiga core use)
         -- (That it is optional, is why the write_en is inverted for the
         -- low-byte).
         -- 16-bit transactions MUST occur on an even numbered address, or
         -- else expect odd and horrible things to happen.
         wdata_hi : in unsigned(7 downto 0) := x"00";
         wen_hi : in std_logic := '0';            
         wen_lo : in std_logic := '1';
         rdata_hi : out unsigned(7 downto 0);
         rdata_16en : in std_logic := '0';         -- set this high to be able
                                                   -- to read 16-bit values
         
         rdata : out unsigned(7 downto 0);
         
         data_ready_strobe : out std_logic := '0';

         -- Starts busy until SDRAM is initialised
         busy : out std_logic := '1';

         -- Export current cache line for speeding up reads from slow_devices controller
         -- by skipping the need to hand us the request and get the response back.
         current_cache_line : out cache_row_t := (others => (others => '0'));
         current_cache_line_address : inout unsigned(26 downto 3) := (others => '0');
         current_cache_line_valid : out std_logic := '0';
         expansionram_current_cache_line_next_toggle : in std_logic := '0';

         -- Allow VIC-IV to request lines of data also.
         -- We then pump it out byte-by-byte when ready
         -- VIC-IV can address only 512KB at a time, so we have a banking register
         viciv_addr : in unsigned(18 downto 3) := (others => '0');
         viciv_request_toggle : in std_logic := '0';
         viciv_data_out : out unsigned(7 downto 0) := x"00";
         viciv_data_strobe : out std_logic := '0';

         -- SDRAM interface (e.g. AS4C16M16SA-6TCN, IS42S16400F, etc.)
         sdram_a     : out unsigned(12 downto 0);
         sdram_ba    : out unsigned(1 downto 0);
         sdram_dq    : inout unsigned(15 downto 0);
         sdram_cke   : out std_logic := '1';
         sdram_cs_n  : out std_logic := '0';
         sdram_ras_n : out std_logic;
         sdram_cas_n : out std_logic;
         sdram_we_n  : out std_logic;
         sdram_dqml  : out std_logic;
         sdram_dqmh  : out std_logic
         
         );
end sdram_controller;

architecture tacoma_narrows of sdram_controller is

  -- The SDRAM requires a 100us setup time
  signal sdram_prepped : std_logic := '0';  
  signal sdram_100us_countdown : integer := 16_200;
  signal sdram_do_init : std_logic := '0';
  signal sdram_init_phase : integer range 0 to 63 := 0;

  type sdram_cmd_t is (CMD_NOP, CMD_SET_MODE_REG,
                       CMD_PRECHARGE,
                       CMD_AUTO_REFRESH,
                       CMD_ACTIVATE_ROW,
                       CMD_READ,
                       CMD_WRITE,
                       CMD_STOP
                       );

  -- Initialisation sequence required for SDRAM according to
  -- the "INITIALIZE AND LOAD MODE REGISTER" section of the
  -- datasheet.
  type sdram_init_t is array (0 to 31) of sdram_cmd_t;
  signal init_cmds : sdram_init_t := (
    2 => CMD_PRECHARGE,
    6 => CMD_AUTO_REFRESH,
    16 => CMD_AUTO_REFRESH,
    26 => CMD_SET_MODE_REG,
    others => CMD_NOP);

  -- SDRAM state machine.  IDLE must be the last in the list,
  -- so that the shallow auto-progression logic can progress
  -- through.
  type sdram_state_t is (PRECHARGE_WAIT,
                         PRECHARGE_WAIT_2,
                         PRECHARGE_WAIT_3,
                         ACTIVATE_WAIT,
                         ACTIVATE_WAIT_2,
                         READ_WAIT,
                         READ_WAIT_2,
                         READ_0,
                         READ_1,
                         READ_2,
                         READ_3,
                         READ_PRECHARGE,
                         READ_PRECHARGE_2,
                         READ_PRECHARGE_3,
                         IDLE);
  signal sdram_state : sdram_state_t := IDLE;

  signal rdata_line : unsigned(63 downto 0);
  signal latched_addr : unsigned(26 downto 0);
  signal rdata_buf : unsigned(7 downto 0);
  signal rdata_hi_buf : unsigned(7 downto 0);
  signal read_latched : std_logic := '0';
  signal write_latched : std_logic := '0';
  signal wdata_latched : unsigned(7 downto 0);
  signal wdata_hi_latched : unsigned(7 downto 0);
  signal latched_wen_lo : std_logic := '0';
  signal latched_wen_hi : std_logic := '0';
  
begin  

  rdata <= (others => 'Z');

  process(clock162,pixelclock) is
    procedure sdram_emit_command(cmd : sdram_cmd_t) is
    begin
      case cmd is
        when CMD_SET_MODE_REG =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '0';
          sdram_we_n <= '0';
        when CMD_PRECHARGE =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '1';
          sdram_we_n <= '0';
          sdram_a(10) <= '1';
        when CMD_AUTO_REFRESH =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '0';
          sdram_we_n <= '1';
        when CMD_ACTIVATE_ROW =>
          -- sdram_ba=BANK and sdram_a=ROW
          sdram_ras_n <= '0';
          sdram_cas_n <= '1';
          sdram_we_n <= '1';
        when CMD_READ =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '0';
          sdram_we_n <= '1';
        when CMD_WRITE =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '0';
          sdram_we_n <= '0';
        when CMD_STOP =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n <= '0';
        when CMD_NOP =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n <= '1';
        when others =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n <= '1';
      end case;
    end procedure;
    
  begin
    if rising_edge(clock162) then

      sdram_dq <= (others => 'Z');
      sdram_dqml <= '1';
      sdram_dqmh <= '1';

      -- Keep logic flat by pre-extracting read data
      case latched_addr(2 downto 0) is
        when "000" =>
          rdata_buf <= rdata_line(7 downto 0);
          rdata_hi_buf <= rdata_line(15 downto 8);
        when "001" =>
          rdata_buf <= rdata_line(15 downto 8);
          rdata_hi_buf <= rdata_line(23 downto 16);
        when "010" =>
          rdata_buf <= rdata_line(23 downto 16);
          rdata_hi_buf <= rdata_line(31 downto 24);
        when "011" =>
          rdata_buf <= rdata_line(31 downto 24);
          rdata_hi_buf <= rdata_line(39 downto 32);
        when "100" =>
          rdata_buf <= rdata_line(39 downto 32);
          rdata_hi_buf <= rdata_line(47 downto 40);
        when "101" =>
          rdata_buf <= rdata_line(47 downto 40);
          rdata_hi_buf <= rdata_line(55 downto 48);
        when "110" =>
          rdata_buf <= rdata_line(55 downto 48);
          rdata_hi_buf <= rdata_line(63 downto 56);
        when others => -- "111" =>
          rdata_buf <= rdata_line(63 downto 56);
          rdata_hi_buf <= rdata_line(7 downto 0);
      end case;
      
      
      -- Latch incoming requests (those come in on the 81MHz pixel clock)
      if read_request='1' and write_request='0' and write_latched='0' and read_latched='0' then
        busy <= '1';
        read_latched <= '1';
        latched_addr <= address;
        wdata_latched <= wdata;
        wdata_hi_latched <= wdata_hi;
      end if;
      if read_request='0' and write_request='1' and write_latched='0' and read_latched='0' then
        busy <= '1';
        read_latched <= '1';
        latched_addr <= address;
        wdata_latched <= wdata;
        wdata_hi_latched <= wdata_hi;
      end if;

      -- Manage the 100usec SDRAM initialisation delay, if enabled
      if sdram_100us_countdown /= 0 then
        sdram_100us_countdown <= sdram_100us_countdown - 1;
      end if;
      if sdram_100us_countdown = 1 then
        report "SDRAM: Starting init sequence after 100usec delay";
        sdram_do_init <= not sdram_prepped;
      end if;
      if enforce_100us_delay = false then
        report "SDRAM: Skipping 100usec init delay";
        sdram_do_init <= not sdram_prepped;
      end if;
      -- And the complete SDRAM initialisation sequence
      if sdram_init_phase = 0 and sdram_do_init='1' then
        report "SDRAM: Starting SDRAM initialisation sequence";
        sdram_init_phase <= 1;
      end if;
      if sdram_prepped='0' then
        if sdram_init_phase /= 0 then
          report "EMIT init phase " & integer'image(sdram_init_phase) & " command "
            & sdram_cmd_t'image(init_cmds(sdram_init_phase));
        end if;

        -- Clear reserved bits for mode register
        sdram_ba <= (others => '0');
        sdram_a(12 downto 10) <= (others => '0');
        -- write burst length = 1
        sdram_a(9) <= '1';
        -- Normal mode of operation
        sdram_a(8 downto 7) <= (others => '0');
        -- CAS latency = 3, for 167MHz operation
        sdram_a(6 downto 4) <= to_unsigned(3,3);
        -- Non-interleaved burst order
        sdram_a(3) <= '0';
        -- Read burst length = 4 x 16 bit words = 8 bytes
        sdram_a(2 downto 0) <= to_unsigned(2,3);

        -- Emit the sequence of commands
        -- MUST BE DONE AFTER SETTING sdram_a
        -- (so that A10 can be set for the PRECHARGE_ALL command,
        --  but stay clear for all the rest)
        sdram_emit_command(init_cmds(sdram_init_phase));
        
        if sdram_init_phase = 31 then
          sdram_prepped <= '1';
          busy <= '0';
          report "SDRAM: Clearing BUSY at end of initialisation sequence";
        elsif sdram_init_phase /= 0 then
          sdram_init_phase <= sdram_init_phase + 1;
        end if;
      else
        -- SDRAM is ready
        if sdram_state /= IDLE then
          sdram_state <= sdram_state_t'succ(sdram_state);
        end if;
        case sdram_state is
          when IDLE =>
            data_ready_strobe <= '0';
            if read_latched='1' or write_latched='1' then
              -- Request ACTIVATE
              sdram_emit_command(CMD_PRECHARGE);              
            end if;
          when PRECHARGE_WAIT =>
            null;
          when PRECHARGE_WAIT_2 =>
            null;
          when PRECHARGE_WAIT_3 =>
              sdram_emit_command(CMD_ACTIVATE_ROW);
              sdram_ba <= latched_addr(25 downto 24);
              sdram_a <= latched_addr(23 downto 11);
              sdram_state <= ACTIVATE_WAIT;
            
          when ACTIVATE_WAIT =>
            sdram_emit_command(CMD_NOP);
          when ACTIVATE_WAIT_2 =>
            sdram_emit_command(CMD_NOP);
            if read_latched='1' then
              sdram_emit_command(CMD_READ);
              -- Select address of start of 8-byte block
              -- Each word is 2 bytes, which takes one bit
              -- off, and then the bottom two bits must be zero.
              sdram_a(12) <= '0';
              sdram_a(11) <= '0';
              sdram_a(10) <= '1'; -- Enable auto precharge
              sdram_a(9 downto 2) <= latched_addr(10 downto 3);
              sdram_a(1 downto 0) <= "00";
              sdram_state <= READ_WAIT;
            end if;
            if write_latched='1' then
              sdram_emit_command(CMD_WRITE);
              sdram_a(12) <= '0';
              sdram_a(11) <= '0';
              sdram_a(10) <= '1'; -- Enable auto precharge
              sdram_a(9 downto 0) <= latched_addr(10 downto 1);
              sdram_state <= READ_PRECHARGE; -- wait for 
              sdram_dqmh <= latched_wen_hi;
              sdram_dqml <= latched_wen_lo;
            end if;
            sdram_dq(7 downto 0) <= wdata_latched;
            sdram_dq(15 downto 8) <= wdata_hi_latched;
          when READ_WAIT =>
            sdram_emit_command(CMD_NOP);
          when READ_WAIT_2 =>
            sdram_emit_command(CMD_NOP);
          when READ_0 =>
            sdram_emit_command(CMD_NOP);
            rdata_line(15 downto 0) <= sdram_dq;
          when READ_1 =>
            sdram_emit_command(CMD_NOP);
            rdata_line(31 downto 16) <= sdram_dq;
          when READ_2 =>
            sdram_emit_command(CMD_NOP);
            rdata_line(47 downto 32) <= sdram_dq;
          when READ_3 =>
            sdram_emit_command(CMD_NOP);
            rdata_line(63 downto 48) <= sdram_dq;
          when READ_PRECHARGE => 
            -- Drive stage to allow selection of buffer output
          when READ_PRECHARGE_2 => 
            rdata <= rdata_buf;
            rdata_hi <= rdata_hi_buf;
            data_ready_strobe <= '1';
          when READ_PRECHARGE_3 =>
            sdram_state <= IDLE;
                        
          when others =>
            null;
        end case;
      end if;
      
    end if;
  end process;
  
end tacoma_narrows;
