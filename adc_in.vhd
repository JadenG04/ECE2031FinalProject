-- ADC_IN.vhd
-- 
-- This module implements an SPI controller customized for an LTC2308 
-- Analog-to-Digital Converter (ADC). 
--
-- Generics:
--   CLK_DIV : Divides the main clock to generate the SCLK frequency.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ADC_IN is
	generic (
		-- Divides the main clock to generate SCLK frequency
		-- Note that there's an additional factor of 2 because
		-- this CLK_DIV factor defines the rate at which SCLK
		-- will rise *and* fall.
		CLK_DIV : integer := 1 
	);
	port (
		-- Control and data for this device
		clk      : in  std_logic; -- clock input
		-- rx_data  : out std_logic_vector(11 downto 0); -- data from ADC
		IO_ADDR	: in std_logic_vector(10 DOWNTO 0);
		IO_READ	: in std_logic;
		IO_DATA	: inout std_logic_vector(15 downto 0);
		
		-- SPI Physical Interface
		sclk     : out std_logic; -- Serial clock
		conv     : out std_logic; -- Conversion start control
		mosi     : out std_logic; -- Data out from this device, in to ADC
		miso     : in  std_logic  -- Data out from ADC, in to this device
	);
end entity ADC_IN;

architecture internals of ADC_IN is
   -- MODIFIED: Internal memory to hold output of ADC every cycle
	signal output_mem	: std_logic_vector(15 downto 0) := "0000000000000000";
	
	-- Expanded state machine to handle conversion wait times
	type state_type is (IDLE, CONV_PULSE, CONV_WAIT, TRANSFER, HOLD);
	signal state : state_type; 
	
	-- Internal signals for clock generation
	signal clk_cnt   : integer range 0 to CLK_DIV;
	signal sclk_int  : std_logic;
	signal sclk_rise : std_logic;
	signal sclk_fall : std_logic;
	
	-- Internal signals for command/control
	signal bit_cnt   : integer range 0 to 12;
	signal wait_cnt  : integer range 0 to 200; -- New counter for 200 clk wait
	-- 200 clk wait, 1 / 100 MHz is 100 ns, 200 * x = 20 micro seconds
	-- Conversion time is 1.6 micro seconds, maybe just being ultra conservative?
	-- EDIT: No, just to be flexible
	
	-- Internal signals for data shifting
	-- The default value here is for a single-ended conversion on channel 0
	constant tx_data : std_logic_vector(11 downto 0) := "100010000000";
	-- default value
	signal tx_reg    : std_logic_vector(11 downto 0);
	signal rx_reg    : std_logic_vector(11 downto 0);

begin
	-------------------------------------------------------------------
	-- Peripheral Handling
	-- Handles peripheral input and output
	-------------------------------------------------------------------
	IO_DATA <= output_mem WHEN (IO_ADDR = "00011000000") AND (IO_READ = '1')
		ELSE "ZZZZZZZZZZZZZZZZ";
	--Apr 6 Allistair: removed 2 extra bits of padding so it's 11 bits
	--Apr 6 Aaron Shansab: changed IO_ADDR to 0000011000000 from 00000000000 b/c address 0... 
	--...This is b/c of the statement in the Peripheral Functinality Page:
	--"SCOMP I/O addresses 0xC0 through 0xCF have been reserved for this peripheral, so you can use any address(es) in that range..."
	
	
	-- Output assignment for the SPI Clock.
	-- An internal version is needed so that logic inside this device can be based on
	-- it (reading an output is not allowed in VHDL).
	sclk <= sclk_int;
	-- feeding output clock to ADC

	-------------------------------------------------------------------
	-- Controlling Process
	-- Handles the wait timer, 
	-- and counts the 12 bits as they are transmitted.
	-------------------------------------------------------------------
	process(clk)
	begin
		-- if active-low reset is active, set everything to 0
		-- if rising edge of clock, start logic
		if rising_edge(clk) then
			case state is
				-- idle state
				when IDLE => -- MODIFIED, wait one clock cycle, go directly to CONV_PULSE
					state   <= CONV_PULSE; -- go from idle to CONV_PULSE
					conv    <= '1'; -- Go high for one clk cycle
					
				when CONV_PULSE =>
					conv     <= '0'; -- Go low to keep ADC awake (pulse)
					wait_cnt <= 85;  -- Set wait timer
					-- 85 ns * 20 = 1.7 microseconds
					state    <= CONV_WAIT; -- go to conv wait
--Aaron Shansab Apr 6: changed from wait_cnt <= 40 to wait_cnt <= 85
--this is b/c DE10 clock speed is 50 MHz, so one cycle is 20 nanoseconds, not 100 nanoseconds
--so 40*20 ns = 800 nanoseconds; ADC will need 1.6 ms to do conversion, VHDL will ask for data before conversion finishes
--switched to 85 cycles for extra time


				when CONV_WAIT =>
					if wait_cnt = 0 then
						state   <= TRANSFER;
						bit_cnt <= 12 - 1;
						-- Go to transfer state, update bit_cnt to 11
					else
						wait_cnt <= wait_cnt - 1;
						-- wait 4 nanoseconds
					end if;

				when TRANSFER =>
					-- Decrement bit count on the rising edge
					-- Loop 11 times, on internal clock 

					if sclk_rise = '1' then
						if bit_cnt = 0 then
							state <= HOLD;
						else
							bit_cnt <= bit_cnt -1;
						end if;
					end if;

						
				--	if sclk_rise = '1' then
					--	bit_cnt <= bit_cnt - 1;
						--if bit_cnt = 0 then
						--	state <= HOLD;
						--end if;
					--end if;
--Apr 6 Aaron Shansab: modified transfer state so that bit_cnt will not be out of bounds on 12th clock cycle
--(see old code above)						
						
				when HOLD =>
					conv  <= '0';
					state <= IDLE; -- MODIFIED, wait one clock cycle, then go back to IDLE 	  
			end case;
		end if;
	end process;

	-------------------------------------------------------------------
	-- Clock Generation Process
	-- Divides the system clock for SCLK and generates flag signals to 
	-- control other parts of the system.
	-------------------------------------------------------------------
	
	-- divides clock by two
	process(clk)
	begin
		if rising_edge(clk) then
			-- Note that because this is in a process, these values
			-- can be "overridden" by lines of code lower in the block.
			sclk_rise <= '0';
			sclk_fall <= '0';
			
			if state = TRANSFER then
				clk_cnt <= clk_cnt + 1;
				if clk_cnt = CLK_DIV - 1 then
					clk_cnt <= 0;
					
					sclk_int <= not sclk_int; -- Toggle SCLK
					if sclk_int = '0' then
						sclk_rise <= '1'; -- SCLK is transitioning 0 -> 1
					else
						sclk_fall <= '1'; -- SCLK is transitioning 1 -> 0
					-- If those IF conditions seem backwards to you, you're
					-- thinking like software instead of thinking like hardware.
					
					end if;
				end if;
			else
				clk_cnt  <= 0;
				sclk_int <= '0'; -- Ensure SCLK idles low
			end if;
		end if;
	end process;

	-------------------------------------------------------------------
	-- Data Process
	-- Manages the TX and RX shift registers.
	-- Samples MISO on rising edges and shifts MOSI out on falling edges.
	-------------------------------------------------------------------
	process(clk)
	begin
		if rising_edge(clk) then
			
			if state = IDLE then
				-- MODIFIED: Load data to transmit immediately on IDLE
				tx_reg <= tx_data;
				mosi   <= tx_data(11); -- Setup the first bit on MOSI
				-- MOSI = master out, slave in, basically, our output to ADC
					 
			elsif state = TRANSFER then
				-- Sample MISO on rising edges
				if sclk_rise = '1' then
					rx_reg <= rx_reg(10 downto 0) & miso;
					-- MISO = master in, slave out, basically, our input from ADC
				end if;
					 
				-- Shift MOSI on falling edges.
				if sclk_fall = '1' then
					tx_reg <= tx_reg(10 downto 0) & '0';
					mosi   <= tx_reg(10); -- Put the next MSB onto the line
				end if;
			
			-- CRUCAIL, hold state latches received data into output bus, can't just get rid of it
			elsif state = HOLD then
				-- Once the last bit is shifted, latch received data onto
				-- the output bus.
			
				output_mem <= "0000" & rx_reg; -- MODIFIED: store to memory instead, leftpad with concatenation
			--Apr 6 Aaron Shansab: removed the line if statement "if sclk_fall = '1' then" as a condition for output_mem <= 6000...
			--...b/c sclk_fall won't equal 1 in the HOLD state
			end if;
			
		end if;
	end process;

end architecture internals;
