library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_iec_serial is
  generic (runner_cfg : string);
end entity;

architecture test_arch of tb_iec_serial is

  signal pixelclock : std_logic := '0';
  signal clock41 : std_logic := '0';

  signal fastio_addr : unsigned(19 downto 0) := x"d3690";
  signal fastio_write : std_logic := '0';
  signal fastio_read : std_logic := '0';
  signal fastio_wdata : unsigned(7 downto 0);
  signal fastio_rdata : unsigned(7 downto 0);

  signal fastio81_addr : unsigned(19 downto 0) := (others => '0');
  signal fastio81_write : std_logic := '0';
  signal fastio81_read : std_logic := '0';
  signal fastio81_wdata : unsigned(7 downto 0);
  signal fastio81_rdata : unsigned(7 downto 0);
  signal cs81_driveram : std_logic := '0';
  
  signal debug_state : unsigned(11 downto 0);
  signal debug_usec : unsigned(7 downto 0);
  signal debug_msec : unsigned(7 downto 0);
  signal iec_state_reached : unsigned(11 downto 0);

  signal drive_cycle_countdown : integer := 0;

  signal iec_reset_n : std_logic;
  signal iec_atn : std_logic;
  signal iec_clk_en_n : std_logic;
  signal iec_data_en_n : std_logic;
  signal iec_srq_en_n : std_logic;
  signal iec_clk_o : std_logic;
  signal iec_data_o : std_logic;
  signal iec_srq_o : std_logic;
  signal iec_clk_i : std_logic := '1';
  signal iec_data_i : std_logic := '1';
  signal iec_srq_i : std_logic := '1';
    
  signal atn_state : integer := 0;

  signal dummy_iec_data : std_logic := '1';
  
  signal f1581_pc : unsigned(15 downto 0);
  signal f1581_reset_n : std_logic := '1';
  signal f1581_cycle_strobe : std_logic := '0';
  signal f1581_clk : std_logic;
  signal f1581_data : std_logic;
  signal f1581_srq : std_logic;

  signal dummy_iec_data_last : std_logic := '1';
  signal f1581_data_last : std_logic := '1';
  signal f1581_clk_last : std_logic := '1';
  signal iec_clk_en_n_last : std_logic := '1';
  signal iec_data_en_n_last : std_logic := '1';
  signal iec_atn_last : std_logic := '1';
  signal power_up : boolean := true;

  signal c1581_received_byte : unsigned(7 downto 0); 

  signal d81_address : unsigned(19 downto 0);
  signal d81_rdata : unsigned(7 downto 0);

  signal host_reset : std_logic := '0';
  signal host_reset_countdown : integer range 0 to 7 := 7;

  signal silence_internal_drive : std_logic := '0';
  
begin

  d81: entity work.d81 port map (
    -- Fast IO interface
    clka => pixelclock,
    csa => '1',
    addressa => to_integer(d81_address(19 downto 0)),
    wea => '0',
    doa => d81_rdata,
    dia => (others => '0'),

    -- CPU interface
    clkb => '1',
    addressb => 0

    );

  
  iec0: entity work.iec_serial generic map (
    cpu_frequency => 40_500_500,
    with_debug => true
    )
    port map (
    clock => clock41,
    clock81 => pixelclock,
    reset_in => host_reset,

    fastio_addr => fastio_addr,
    fastio_write => fastio_write,
    fastio_read => fastio_read,
    fastio_wdata => fastio_wdata,
    fastio_rdata => fastio_rdata,

    debug_state => debug_state,
    debug_usec => debug_usec,
    debug_msec => debug_msec,

    iec_state_reached => iec_state_reached,

    iec_reset_n => iec_reset_n,
    iec_atn_en_n => iec_atn,
    iec_clk_en_n => iec_clk_en_n,
    iec_data_en_n => iec_data_en_n,
    iec_srq_en_n => iec_srq_en_n,
    iec_clk_i => iec_clk_i,
    iec_data_i => iec_data_i,
    iec_srq_i => iec_srq_i
    
    );

  c1581: entity work.internal1581
    port map (
      clock => clock41,

      silence_internal_drive => silence_internal_drive,
      
      fastio_read => fastio81_read,
      fastio_write => fastio81_write,
      fastio_address => fastio81_addr,
      fastio_wdata => fastio81_wdata,
      fastio_rdata => fastio81_rdata,
      cs_driverom => '0',
      cs_driveram => cs81_driveram,

      last_rx_byte => c1581_received_byte,
      
      address_next => f1581_pc,

      drive_clock_cycle_strobe => f1581_cycle_strobe,
      drive_reset_n => f1581_reset_n,
      drive_suspend => '0',

      -- A bit of a simplification for the IEC lines:
      -- If the IEC controller is driving the lines, we assume
      -- it is driving them low, not high (which it never does).
      -- Ideally we would have <= (iec_clk_en_n and iec_clk_out)
      -- etc.
      iec_atn_i => iec_atn,
      iec_clk_i => iec_clk_i,
      iec_data_i => iec_data_i,
      iec_srq_i => iec_srq_i,

      iec_clk_o => f1581_clk,
      iec_data_o => f1581_data,
      iec_srq_o => f1581_srq,
      
      sd_data_byte => x"00",
      sd_data_ready_toggle => '0'
      
      );

  process (clock41) is
    variable show_update : boolean := false;
  begin
    if rising_edge(clock41) then
            
      -- Compute effective IEC line voltages
      iec_data_i <= dummy_iec_data and f1581_data and iec_data_en_n;
      iec_clk_i <= f1581_clk and iec_clk_en_n;

      -- Do we need to show an update to the IEC bus state?
      show_update := false;
      if power_up then
        power_up <= false;
        show_update := true;
      end if;
      f1581_data_last <= f1581_data;
      f1581_clk_last <= f1581_clk;
      iec_clk_en_n_last <= iec_clk_en_n;
      iec_data_en_n_last <= iec_data_en_n;
      iec_atn_last <= iec_atn;
      dummy_iec_data_last <= dummy_iec_data;
      if f1581_clk /= f1581_clk_last then
        show_update := true;
      end if;
      if f1581_data /= f1581_data_last then
        show_update := true;
      end if;
      if iec_clk_en_n /= iec_clk_en_n_last then
        show_update := true;
      end if;
      if iec_data_en_n /= iec_data_en_n_last then
        show_update := true;
      end if;
      if iec_atn /= iec_atn_last then
        show_update := true;
      end if;
      if dummy_iec_data /= dummy_iec_data_last then
        show_update := true;
      end if;
      if show_update then
        report "IECBUSSTATE: "
          & "ATN=" & std_logic'image(iec_atn)
          & ", CLK(c64)=" & std_logic'image(iec_clk_en_n)
          & ", CLK(1581)=" & std_logic'image(f1581_clk)
          & ", DATA(c64)=" & std_logic'image(iec_data_en_n)
          & ", DATA(1581)=" & std_logic'image(f1581_data)
          & ", DATA(dummy)=" & std_logic'image(dummy_iec_data)
          ;
      end if;
    end if;
  end process;
  
  
  main : process

    procedure clock_tick is
    begin
      pixelclock <= not pixelclock;
      if pixelclock='1' then
        clock41 <= not clock41;
        if clock41 = '1' then
          if drive_cycle_countdown /= 0 then
            drive_cycle_countdown <= drive_cycle_countdown - 1;
            f1581_cycle_strobe <= '0';
          else
            drive_cycle_countdown <= 20;
            f1581_cycle_strobe <= '1';
            -- Release /RESET line on 4541 IEC host controller after a few cycles.
            -- This is necessary as host timing values are only loaded by the
            -- 4541 when reset is low.
            if host_reset_countdown > 0 then
              host_reset_countdown <= host_reset_countdown - 1;
            else
              host_reset <= '1';
            end if;
          end if;
        end if;
      end if;
      wait for 6.173 ns;
    end procedure;

    procedure boot_1581 is
    begin
      report "IEC: Allowing time for 1581 to boot";
      
      -- Give the 1581 just time enough to boot
      for i in 1 to 2_800_000 loop
        clock_tick;
      end loop;
      report "1581BOOT: Time for drive to boot expired";
      
    end procedure;

    procedure atn_release is
    begin
      report "IEC: Release ATN line and abort any command in progress";
      fastio_write <= '1';
      fastio_addr(3 downto 0) <= x"8";
      fastio_wdata <= x"00"; -- Cancel any command in progress
      for i in 1 to 4 loop
        clock_tick;
      end loop;
      fastio_write <= '0';

      -- Allow time for it to run command
      for i in 1 to 1000 loop
        clock_tick;
      end loop;
      
      fastio_write <= '1';
      fastio_addr(3 downto 0) <= x"8";
      fastio_wdata <= x"41"; -- Trigger release ATN
      for i in 1 to 4 loop
        clock_tick;
      end loop;
      fastio_write <= '0';
      
      -- Allow some time after releasing ATN
      for i in 1 to 10000 loop
        clock_tick;
      end loop;
    end procedure;

    procedure PEEK(a : unsigned(15 downto 0)) is
    begin
        fastio_addr(3 downto 0) <= a(3 downto 0);
        fastio_read <= '1';
        for i in 1 to 8 loop
          clock_tick;
        end loop;
        fastio_read <= '0';      
    end procedure;
    
    procedure POKE(a : unsigned(15 downto 0); v : unsigned(7 downto 0)) is
    begin
        fastio_addr(3 downto 0) <= a(3 downto 0);
        fastio_wdata <= v;
        fastio_write <= '1';
        for i in 1 to 4 loop
          clock_tick;
        end loop;
        fastio_write <= '0';
        for i in 1 to 4 loop
          clock_tick;
        end loop;
    end procedure;

    -- XXX This routine doesn't seem to work
    procedure PEEK81(a : unsigned(15 downto 0)) is
    begin
      fastio81_addr(19 downto 16) <= "0000";
      fastio81_addr(15 downto 0) <= a;
      cs81_driveram <= '1';
      fastio81_read <= '1';
      for i in 1 to 16 loop
        clock_tick;
      end loop;
      cs81_driveram <= '1';
      fastio81_read <= '0';      
    end procedure;

    -- XXX Does this routine work?
    procedure POKE81(a : unsigned(15 downto 0); v : unsigned(7 downto 0)) is
    begin
      fastio81_addr(19 downto 16) <= "0000";
      fastio81_addr(15 downto 0) <= a;
      cs81_driveram <= '1';
      fastio81_wdata <= v;
      fastio81_write <= '1';
      for i in 1 to 4 loop
        clock_tick;
      end loop;
      fastio81_write <= '0';
      cs81_driveram <= '0';
    end procedure;

    procedure load_dirtrack is
    begin
      report "IEC: Loading track 40 into 1581 directory cache from d81.vhdl";
      for i in 0 to (5*1024) loop
        d81_address <= to_unsigned(i,20);
        clock_tick; clock_tick;
        POKE81(to_unsigned(12*256 + i,16), d81_rdata);
        PEEK81(to_unsigned(12*256 + i,16));
        if d81_rdata /= fastio81_rdata then
          assert false report "Read-back of 1581 RAM at $" & to_hexstring(to_unsigned(12*256 + i,16)) & " yielded $" & to_hexstring(fastio81_rdata) & " instead of $" & to_hexstring(d81_rdata);
        end if;
      end loop;

      -- BAM sector 1 to 40 at $0A00
      for i in 0 to 255 loop
        d81_address <= to_unsigned(1*256 + i,20);
        clock_tick; clock_tick;
        POKE81(to_unsigned(10*256 + i,16), d81_rdata);
        PEEK81(to_unsigned(10*256 + i,16));
      end loop;
      -- Disk header to $0900
      for i in 0 to 255 loop
        d81_address <= to_unsigned(0*256 + i,20);
        clock_tick; clock_tick;
        POKE81(to_unsigned(9*256 + i,16), d81_rdata);
        PEEK81(to_unsigned(9*256 + i,16));
      end loop;
      -- First directory sector to $0700
      for i in 0 to 255 loop
        d81_address <= to_unsigned(3*256 + i,20);
        clock_tick; clock_tick;
        POKE81(to_unsigned(7*256 + i,16), d81_rdata);
        PEEK81(to_unsigned(7*256 + i,16));
      end loop;
      
      -- Set track cache track and side numbers
      POKE81(to_unsigned(149,16),to_unsigned(39,8));  -- physical track number
      POKE81(to_unsigned(150,16),to_unsigned(40,8));  -- translated track number
      POKE81(to_unsigned(151,16),to_unsigned(0,8));   -- side number

      -- Spoof disk 0 ready, and without errors
      POKE81(x"008A",x"00");
      POKE81(x"006E",x"00");
      
      
      report "IEC: Finished loading directory track into cache";
  
    end procedure;       

    procedure wait_a_while(t : integer) is
    begin        
      -- Allow time for everything to happen
      for i in 1 to t loop
        clock_tick;
      end loop;
      report "IEC state reached = $" & to_hexstring(iec_state_reached) & " = " & integer'image(to_integer(iec_state_reached));
    end procedure;

    procedure wait_until_READY is
    begin        
      -- Allow time for everything to happen
      for i in 1 to 1_000_000 loop
        PEEK(x"D697");
        if fastio_rdata(5)='1' then
          report "Waited " & integer'image(i) & " iterations for READY to be asserted";
          exit;
        end if;
      end loop;

    end procedure;
    
    procedure wait_and_check_READY(t : integer) is
    begin        
      wait_a_while(t);
      
      -- Expect BUSY flag to have cleared
      PEEK(x"D697");
      report "IEC IRQ status byte = $" & to_hexstring(fastio_rdata);
      if fastio_rdata(5)='0' then
        assert false report "Expected to see ready for command indicated in bit 5 of $D697, but it wasn't";
      end if;
    end procedure;    

    procedure fail_if_DEVICE_NOT_PRESENT is
    begin
      PEEK(x"D698");
      report "IEC status byte = $" & to_hexstring(fastio_rdata);
      if fastio_rdata(7)='1' then
        assert false report "Expected to not see DEVICE NOT PRESENT indicated in bit 7 of $D698, but it was";
      end if;
    end procedure;

    procedure fail_if_DEVICE_PRESENT is
    begin
      PEEK(x"D698");
      report "IEC status byte = $" & to_hexstring(fastio_rdata);
      if fastio_rdata(7)='0' then
        assert false report "Expected to see DEVICE NOT PRESENT indicated in bit 7 of $D698, but a device was found";
      end if;
    end procedure;
    
    procedure fail_if_NO_TIMEOUT is
    begin
      PEEK(x"D698");
      if fastio_rdata(1)='0' then
        assert false report "Expected to see TIMEOUT indicated in bit 1 of $D698, but it wasn't";
      end if;
    end procedure;        

    procedure fail_if_TIMEOUT is
    begin
      PEEK(x"D698");
      if fastio_rdata(1)='1' then
        assert false report "Expected to not see TIMEOUT indicated in bit 1 of $D698, but it was";
      end if;
    end procedure;        

    procedure fail_if_BUSY is
    begin
      PEEK(x"D697");
      report "IEC IRQ status byte = $" & to_hexstring(fastio_rdata);
      if fastio_rdata(5)='0' then
        assert false report "Expected to see ready for command indicated in bit 5 of $D697, but it wasn't";
      end if;
    end procedure;

    procedure fail_if_READY is
    begin
      PEEK(x"D697");
      report "IEC IRQ status byte = $" & to_hexstring(fastio_rdata);
      if fastio_rdata(5)='1' then
        assert false report "Expected to see IEC bus busy in bit 5 of $D697, but it wasn't";
      end if;
    end procedure;

    procedure get_drive_capability is
    begin
      PEEK(x"D69A");

      case fastio_rdata(6 downto 5) is
        when "01" => report "DRIVEINFO: Drive is offering C128 fast serial protocol";
        when "10" => report "DRIVEINFO: Drive is offering JiffyDOS fast serial protocol";
        when "11" => report "DRIVEINFO: Drive is offering JiffyDOS and C128 fast serial protocols";
        when others => report "DRIVEINFO: Drive is supports only slow Commodore serial protocol";
      end case;
    end procedure;
    
    procedure fail_if_JIFFYDOS_CAPABLE is
    begin
      get_drive_capability;
      
      if fastio_rdata(6)='1' then
        assert false report "Drive reports JiffyDOS capable, but this is not allowed.";
      end if;
    end procedure;        

    procedure fail_if_NOT_JIFFYDOS_CAPABLE is
    begin
      get_drive_capability;
      
      if fastio_rdata(6)='1' then
        assert false report "Drive is not JiffyDOS capable, but this is required.";
      end if;
    end procedure;        

    procedure check_1581_last_rx_byte ( v : unsigned(7 downto 0)) is
    begin
      if c1581_received_byte /= v then
        assert false report "1581 expected to receive $" & to_hexstring(v) & ", but received $" & to_hexstring(c1581_received_byte);
      else
        report "1581 correctly received the byte $" & to_hexstring(c1581_received_byte);
      end if;
    end procedure;          
        
    procedure atn_tx_byte(v : unsigned(7 downto 0)) is
    begin
      report "IEC: atn_tx_byte($" & to_hexstring(v) & ")";
      POKE(x"D699",v);
      POKE(x"D698",x"30"); -- Trigger ATN write

      wait_until_READY;

      fail_if_BUSY;
      fail_if_DEVICE_NOT_PRESENT;
      fail_if_TIMEOUT;

      check_1581_last_rx_byte(v);
      
    end procedure;    

    procedure iec_tx(v : unsigned(7 downto 0)) is
    begin 
      report "IEC: iec_tx($" & to_hexstring(v) & ")";
      POKE(x"D699",v);
      POKE(x"D698",x"31"); -- Trigger TX byte without attention

      wait_until_READY;

      fail_if_BUSY;
      fail_if_DEVICE_NOT_PRESENT;
      fail_if_TIMEOUT;

      check_1581_last_rx_byte(v);
      
    end procedure;    

    procedure iec_tx_eoi(v : unsigned(7 downto 0)) is
    begin 
      report "IEC: iec_tx_eoi($" & to_hexstring(v) & ")";

      POKE(x"D699",v);
      POKE(x"D698",x"34"); -- Trigger TX byte without attention, with EOI

      wait_until_READY;

      fail_if_BUSY;
      fail_if_DEVICE_NOT_PRESENT;
      fail_if_TIMEOUT;

      check_1581_last_rx_byte(v);
      
    end procedure;    
    
    procedure tx_to_rx_turnaround is
    begin
      report "IEC: tx_to_rx_turnaround() called.";

      POKE(x"D698",x"35"); -- Trigger turn-around to listen
      
      -- Allow a little time and check status goes busy
      for i in 1 to 100 loop
        clock_tick;
      end loop;
      
      -- Expect BUSY flag to have set
      fail_if_READY;

      -- Don't wait any longer than necessary, as want to make the test
      -- sensitive to the time delay that the turn-around imposes for
      -- the JiffyDOS protocol, where this is important.
      wait_until_READY;

      fail_if_DEVICE_NOT_PRESENT;
      fail_if_TIMEOUT;

      report "IEC: tx_to_rx_turnaround() complete.";
      
    end procedure;

    procedure iec_rx(expected : unsigned(7 downto 0)) is
    begin
      report "IEC: iec_rx($" & to_hexstring(expected) & ")";

      POKE(x"D698",x"32"); -- Trigger RECEIVE BYTE
      
      -- Allow a little time and check status goes busy
      for i in 1 to 100 loop
        clock_tick;
      end loop;

      fail_if_READY;

      wait_until_READY;

      fail_if_BUSY;
      fail_if_DEVICE_NOT_PRESENT;
      fail_if_TIMEOUT;

      -- Read data byte and check against expected
      PEEK(x"D699");
      report "IEC data byte = $" & to_hexstring(fastio_rdata) & " (expected $" & to_hexstring(expected) & ")";
      if fastio_rdata /= expected then
        assert false report "Data byte value was different to expected value";
      end if;      
    end procedure;

    procedure iec_rx_eoi(expected : unsigned(7 downto 0)) is
    begin
      report "IEC: iec_rx($" & to_hexstring(expected) & ")";
      POKE(x"D698",x"32"); -- Trigger RECEIVE BYTE
      
      -- Allow a little time and check status goes busy
      for i in 1 to 100 loop
        clock_tick;
      end loop;

      -- Expect BUSY flag to have set
      fail_if_READY;

      wait_until_READY;

      fail_if_BUSY;
      fail_if_DEVICE_NOT_PRESENT;
      fail_if_TIMEOUT;

      PEEK(x"D698");
      if fastio_rdata(6)='1' then
        report "Saw EOI";
      else
        assert false report "Character received without EOI";
      end if;

      -- Read data byte and check against expected
      PEEK(x"D699");
      report "IEC data byte = $" & to_hexstring(fastio_rdata) & " (expected $" & to_hexstring(expected) & ")";
      if fastio_rdata /= expected then
        assert false report "Data byte value was different to expected value";
      end if;      
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);    
    
    while test_suite loop

      if run("Simulated 1581 runs") then
        -- 3x10^6 x 81MHz ticks = ~20msec. Plenty enough for getting to main loop
        -- of drive. (Needs >3x10^6 to get to $73 in DOS error code table).
        for i in 1 to 3_000_000 loop
          clock_tick;
        end loop;
      elsif run("ATN Sequence with no device gets DEVICE NOT PRESENT") then

        -- Hold 1581 under reset, so that it can't answer
        f1581_reset_n <= '0';

        silence_internal_drive <= '1';

        -- wait for host reset to complete
        while host_reset_countdown /= 0 loop
          clock_tick;
        end loop;
        for i in 1 to 1000 loop
          clock_tick;
        end loop;

        POKE(x"D699",x"29"); -- Access device 9 (drive is device 8, so shouldn't respond)
        POKE(x"D698",x"30"); -- Trigger ATN write

        wait_and_check_READY(4000000);

        fail_if_DEVICE_PRESENT;
        fail_if_NO_TIMEOUT;

      elsif run("Debug RAM can be read") then

        POKE(x"D699",x"29"); -- Access device 9 (drive is device 8, so shouldn't respond)
        POKE(x"D698",x"30"); -- Trigger ATN write

        -- Allow some time for some data to be collected. But we don't care
        -- whether the job finishes or not.
        wait_a_while(400_000);

        -- Now read back debug RAM content

        -- Reset read point to start of debug RAM
        POKE(x"D691",x"00");

        report "Starting readback of debug RAM";
        
        fastio_addr(3 downto 0) <= x"4";
        for n in 0 to 127 loop
          PEEK(x"D694");

          report "Read $" & to_hexstring(fastio_rdata) & " from debug RAM.";

          POKE(x"D694",x"01");

        end loop;
                  
      elsif run("ATN Sequence with dummy device succeeds") then

        -- Hold simulated 1581 under reset, so that it can't interfere
        -- (JiffyDOS ROM at least holds DATA low during boot-up).
        f1581_reset_n <= '0';
        silence_internal_drive <= '1';

        -- wait for host reset to complete
        while host_reset_countdown /= 0 loop
          clock_tick;
        end loop;
        for i in 1 to 1000 loop
          clock_tick;
        end loop;
        
        POKE(x"D699",x"28"); -- Access device 8
        POKE(x"D698",x"30"); -- Trigger ATN write

        -- Now pretend to be a simple IEC device
        for i in 1 to 800000 loop
          clock_tick;
          if iec_atn='0' then
            if iec_atn_last = '1' then
              report "TESTBED: ATN has gone low";
            end if;
            if true then
              -- Pretend there is a device
              if atn_state = 0 and iec_clk_i = '0' then
                atn_state <= 1;
                report "TESTBED: Pulling DATA to 0V";
                dummy_iec_data <= '0';
              end if;
              if atn_state = 1 and iec_clk_i = '1' then
                atn_state <= 2;
                dummy_iec_data <= '1';
                report "TESTBED: Releasing DATA to 5V";
              end if;
              if atn_state = 2 and iec_clk_i = '0' then
                atn_state <= 3;
              end if;
              if atn_state = 2 and iec_clk_i = '0' then
                atn_state <= 3;
              end if;
              -- Then watch first 7 bits arrive, then signal JiffyDOS support
              if atn_state = 2 and iec_clk_i = '0' then atn_state <= atn_state + 1; end if;
              if atn_state = 3 and iec_clk_i = '1' then atn_state <= atn_state + 1; end if;
              if atn_state = 4 and iec_clk_i = '0' then atn_state <= atn_state + 1; end if;
              if atn_state = 5 and iec_clk_i = '1' then atn_state <= atn_state + 1; end if;
              if atn_state = 6 and iec_clk_i = '0' then atn_state <= atn_state + 1; end if;
              if atn_state = 7 and iec_clk_i = '1' then atn_state <= atn_state + 1; end if;
              if atn_state = 8 and iec_clk_i = '0' then atn_state <= atn_state + 1; end if;
              if atn_state = 9 and iec_clk_i = '1' then atn_state <= atn_state + 1; end if;
              if atn_state = 10 and iec_clk_i = '0' then atn_state <= atn_state + 1; end if;
              if atn_state = 11 and iec_clk_i = '1' then atn_state <= atn_state + 1; end if;
              if atn_state = 12 and iec_clk_i = '0' then atn_state <= atn_state + 1; end if;
              if atn_state = 13 and iec_clk_i = '1' then atn_state <= atn_state + 1; end if;
              if atn_state = 14 and iec_clk_i = '0' then atn_state <= atn_state + 1; end if;
              if atn_state = 15 and iec_clk_i = '1' then atn_state <= atn_state + 1; end if;
              if atn_state = 16 and iec_clk_i = '0' then
                atn_state <= atn_state + 1;
                dummy_iec_data <= '0';
                report "TESTBED: Pulling DATA to 0V to kludge indication of JiffyDOS support ";
                for j in 1 to 12 loop
                  clock_tick;
                end loop;
                dummy_iec_data <= '1';
              end if;
              if atn_state = 17 and iec_clk_i = '1' then atn_state <= atn_state + 1; end if;
              if atn_state = 18 and iec_clk_i = '0' then
                atn_state <= atn_state + 1;
                dummy_iec_data <= '0';
                report "TESTBED: Pulling DATA to 0V to kludge indication of byte acknowledgement ";
              end if;
            end if;
          end if;
        end loop;
        report "IEC state reached = " & to_hexstring(iec_state_reached);

        -- Expect BUSY flag to have cleared
        fail_if_BUSY;
        fail_if_DEVICE_NOT_PRESENT;
        fail_if_TIMEOUT;
        
      elsif run("ATN Sequence with VHDL 1581 device succeeds with JiffyDOS and C128 FAST disabled") then

        boot_1581;
        
        POKE(x"D698",x"6A"); -- Disable JiffyDOS
        POKE(x"D698",x"66"); -- Disable C128 FAST serial
      
        report "IEC: Commencing sending byte under ATN";

        -- Access device 9 (which isn't actually
        -- present, the VHDL device is 8, but
        -- this situation doesn't get detected as
        -- device not present).
        POKE(x"D699",x"29");
        POKE(x"D698",x"30"); -- Trigger ATN write

        wait_until_READY;

        fail_if_DEVICE_NOT_PRESENT;
        fail_if_TIMEOUT;
        fail_if_JIFFYDOS_CAPABLE;        

      elsif run("ATN Sequence with VHDL 1581 device succeeds") then

        boot_1581;

        report "IEC: Commencing sending byte under ATN";
        
        -- Access device 9 (which isn't actually
        -- present, the VHDL device is 8, but
        -- this situation doesn't get detected as
        -- device not present).
        POKE(x"D699",x"29");        
        POKE(x"D698",x"30"); -- Trigger ATN write

        wait_until_READY;

        fail_if_DEVICE_NOT_PRESENT;
        fail_if_TIMEOUT;
        
      elsif run("Read from Error Channel (15) of VHDL 1581 device succeeds with JiffyDOS and C128 FAST disabled") then

        -- Send $48, $6F under ATN, then do turn-around to listen, and receive
        -- 73,... status message from the drive.

        boot_1581;
        
        POKE(x"D698",x"6A"); -- Disable JiffyDOS
        POKE(x"D698",x"66"); -- Disable C128 FAST serial        

        report "IEC: Commencing sending DEVICE 8 TALK ($48) byte under ATN";
        atn_tx_byte(x"48"); -- Device 8 TALK

        report "IEC: Commencing sending SECONDARY ADDRESS 15 byte under ATN";
        atn_tx_byte(x"6F");

        report "IEC: Commencing turn-around to listen";
        tx_to_rx_turnaround;

        report "IEC: Trying to receive a byte";

        -- Check for first 3 bytes of "73,CBM DOS.. / 73,JIFFY DOS...." message
        iec_rx(x"37");
        iec_rx(x"33");
        iec_rx(x"2c");        

        fail_if_JIFFYDOS_CAPABLE;
        

      elsif run("Read from Error Channel (15) of VHDL 1581 device succeeds") then

        -- Send $48, $6F under ATN, then do turn-around to listen, and receive
        -- 73,... status message from the drive.

        boot_1581;

        report "IEC: Commencing sending DEVICE 8 TALK ($48) byte under ATN";
        atn_tx_byte(x"48"); -- Device 8 TALK

        report "IEC: Commencing sending SECONDARY ADDRESS 15 byte under ATN";
        atn_tx_byte(x"6F");

        get_drive_capability;
        
        report "IEC: Commencing turn-around to listen";
        tx_to_rx_turnaround;

        report "IEC: Trying to receive a byte";
        
        -- Check for first 3 bytes of "73,CBM DOS... / 73,JIFFY DOS..." message
        iec_rx(x"37");
        iec_rx(x"33");
        iec_rx(x"2c");

      elsif run("Read from Error Channel (15) of VHDL 1581 with SRQ low") then

        iec_srq_i <= '0';        
        
        -- Send $48, $6F under ATN, then do turn-around to listen, and receive
        -- 73,... status message from the drive.

        boot_1581;

        report "IEC: Commencing sending DEVICE 8 TALK ($48) byte under ATN";
        atn_tx_byte(x"48"); -- Device 8 TALK

        report "IEC: Commencing sending SECONDARY ADDRESS 15 byte under ATN";
        atn_tx_byte(x"6F");

        get_drive_capability;
        
        report "IEC: Waiting a while before performing turn around...";
        wait_until_READY;
        
        report "IEC: Commencing turn-around to listen";

        tx_to_rx_turnaround;

        report "IEC: Trying to receive a few bytes";

        -- Check for first 3 bytes of "73,CBM DOS... / 73,JIFFY DOS..." message
        iec_rx(x"37");
        iec_rx(x"33");
        iec_rx(x"2c");
        
      elsif run("Read from Error Channel (15) of VHDL 1581 with delay before turn-around") then

        -- Send $48, $6F under ATN, then do turn-around to listen, and receive
        -- 73,... status message from the drive.

        boot_1581;

        report "IEC: Commencing sending DEVICE 8 TALK ($48) byte under ATN";
        atn_tx_byte(x"48"); -- Device 8 TALK

        report "IEC: Commencing sending SECONDARY ADDRESS 15 byte under ATN";
        atn_tx_byte(x"6F");

        get_drive_capability;

        report "IEC: Waiting a while before performing turn around...";
        wait_and_check_READY(800_000);

        report "IEC: Commencing turn-around to listen";
        tx_to_rx_turnaround;

        report "IEC: Trying to receive a few bytes";

        -- Check for first 3 bytes of "73,CBM DOS... / 73,JIFFY DOS..." message
        iec_rx(x"37");
        iec_rx(x"33");
        iec_rx(x"2c");
        
      elsif run("Drive Byte RX Bit Order and Polarity") then

        boot_1581;

        report "IEC: Commencing sending DEVICE 8 LISTEN ($28) byte under ATN";
        atn_tx_byte(x"28"); -- Device 8 LISTEN

        report "IEC: Commencing sending OPEN SECONDARY ADDRESS 15 byte under ATN";
        atn_tx_byte(x"FF"); -- Some documentation claims $FF should be used
                            -- here, but that yields device not present on the
                            -- VHDL 1581 for some reason?  $6F seems to work, though?

        get_drive_capability;
        
        report "Clearing ATN";
        atn_release;       
        
        report "IEC: Bytes with each single bit set";
        
        iec_tx(x"01");
        iec_tx(x"02"); 
        iec_tx(x"04"); 
        iec_tx(x"08");
        iec_tx(x"10");
        iec_tx(x"20");
        iec_tx(x"40");
        iec_tx(x"80");
        

      elsif run("Write to and read from Command Channel (15) of VHDL 1581 device succeeds") then

        -- Send LISTEN to device 8, channel 15, send the "UI-" command, then
        -- Send TALK to device 8, channel 15, and read back 00,OK,00,00 message
        
        boot_1581;

        report "IEC: Commencing sending DEVICE 8 LISTEN ($28) byte under ATN";
        atn_tx_byte(x"28"); -- Device 8 LISTEN

        report "IEC: Commencing sending OPEN SECONDARY ADDRESS 15 byte under ATN";
        atn_tx_byte(x"FF"); -- Some documentation claims $FF should be used
                            -- here, but that yields device not present on the
                            -- VHDL 1581 for some reason?  $6F seems to work, though?

        get_drive_capability;
        
        report "Clearing ATN";
        atn_release;       
        
        report "IEC: Sending UI- command";
        iec_tx(x"55");  -- U
        iec_tx(x"49");  -- I
        iec_tx_eoi(x"2D");  -- +
             
        report "IEC: Sending UNLISTEN to device 8";
        atn_tx_byte(x"3F");

           
        report "Clearing ATN";
        atn_release;

        -- Processing the command takes quite a while, because we have to do
        -- that whole computationally expensive retrieval of error message text
        -- from tokens thing.
        report "IEC: Allow 1581 time to process the UI- command.";
        wait_a_while(300_000);
        
        report "IEC: Request read command channel 15 of device 8";
        atn_tx_byte(x"48");
        atn_tx_byte(x"6f");

        report "IEC: Commencing turn-around to listen";
        tx_to_rx_turnaround;

        report "IEC: Trying to receive a byte";
        -- Check for "00, OK,00,00" message
        iec_rx(x"30");
        iec_rx(x"30");
        iec_rx(x"2C");
        iec_rx(x"20");
        iec_rx(x"4F");
        iec_rx(x"4B");
        iec_rx(x"2C");
        iec_rx(x"30");
        iec_rx(x"30");
        iec_rx(x"2C");
        iec_rx(x"30");
        iec_rx(x"30");
        iec_rx_eoi(x"0D");        

      elsif run("Load directory") then

        
        boot_1581;

        report "CHECKPOINT 1";
        
        -- Modify 1581's RAM contents, so that it thinks track 40 has been
        -- loaded already
        load_dirtrack;
        
        report "IEC: Commencing sending DEVICE 8 LISTEN ($28) byte under ATN";
        atn_tx_byte(x"28"); -- Device 8 LISTEN

        report "CHECKPOINT 2";

        report "IEC: Commencing sending OPEN SECONDARY ADDRESS 0 byte under ATN";
        atn_tx_byte(x"F0");

        report "CHECKPOINT 3";

        get_drive_capability;
        
        report "CHECKPOINT 4";
        
        report "Clearing ATN";
        atn_release;       

        report "CHECKPOINT 5";

        report "IEC: Sending $ filename";
        iec_tx_eoi(x"24");  -- $

        report "CHECKPOINT 6";
        
        report "IEC: Sending UNLISTEN to device 8";
        atn_tx_byte(x"3F");

        report "CHECKPOINT 7";
        
        report "Clearing ATN";
        atn_release;

        report "CHECKPOINT 8";
        
        report "IEC: Allow 1581 time to process the $ filename.";
        wait_a_while(3_000_000);

        report "CHECKPOINT 9";
        
        report "IEC: Request read command channel 0 of device 8";
        atn_tx_byte(x"48");
        report "CHECKPOINT 10";
        atn_tx_byte(x"60");
        report "CHECKPOINT 11";

        report "IEC: Commencing turn-around to listen";
        tx_to_rx_turnaround;

        report "CHECKPOINT 12";
        
        report "IEC: Trying to receive a byte";
        -- Check for correct directory listing for our disk image
        iec_rx(x"01");
        iec_rx(x"04");
        iec_rx(x"01");
        iec_rx(x"01");
        iec_rx(x"00");
        iec_rx(x"00");
        iec_rx(x"12");
        iec_rx(x"22");
        iec_rx(x"43");
        iec_rx(x"42");
        iec_rx(x"4D");
        iec_rx(x"43");
        iec_rx(x"4F");
        iec_rx(x"4E");
        iec_rx(x"56");
        iec_rx(x"45");
        iec_rx(x"52");
        iec_rx(x"54");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"32");
        iec_rx(x"2E");
        iec_rx(x"30");
        iec_rx(x"22");
        iec_rx(x"20");
        iec_rx(x"39");
        iec_rx(x"38");
        iec_rx(x"20");
        iec_rx(x"33");
        iec_rx(x"44");
        iec_rx(x"00");
        iec_rx(x"01");
        iec_rx(x"01");
        -- It succeeds to here, then gets wrong data, because contents of
        -- buffer at $08xx are being set by 1581 DOS, and I haven't looked into
        -- what I have wrong in the side-loading of the track 40 cache etc.
        -- I'm not worried about it for now, because the test getting this far
        -- proves that LOAD starts to work, which is all I was testing. #736
        iec_rx(x"DC");
        iec_rx(x"00");
        iec_rx(x"20");
        iec_rx(x"22");
        iec_rx(x"CD");
        iec_rx(x"41");
        iec_rx(x"4B");
        iec_rx(x"45");
        iec_rx(x"46");
        iec_rx(x"49");
        iec_rx(x"4C");
        iec_rx(x"45");
        iec_rx(x"22");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"50");
        iec_rx(x"52");
        iec_rx(x"47");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"00");
        iec_rx(x"01");
        iec_rx(x"01");
        iec_rx(x"7C");
        iec_rx(x"0B");
        iec_rx(x"42");
        iec_rx(x"4C");
        iec_rx(x"4F");
        iec_rx(x"43");
        iec_rx(x"4B");
        iec_rx(x"53");
        iec_rx(x"20");
        iec_rx(x"46");
        iec_rx(x"52");
        iec_rx(x"45");
        iec_rx(x"45");
        iec_rx(x"2E");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"20");
        iec_rx(x"00");
        iec_rx_eoi(x"00");
        
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
