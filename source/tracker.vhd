LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE work.ALL;
USE work.budpack.ALL;

ENTITY tracker IS
  PORT(
    clk           : IN  std_logic;
    reset         : IN  std_logic;
    start         : IN  std_logic;
    group_addr_in : IN  std_logic_vector(31 DOWNTO 0);
    size          : IN  std_logic_vector(31 DOWNTO 0);
    flag_alloc    : IN  std_logic;      -- 0 = free, 1 = malloc
    func_sel      : IN  std_logic;  -- 0 = update, 1 = make a probe for search
    done_bit      : OUT std_logic;
    probe_out     : OUT tree_probe;
    ram_we        : OUT std_logic;
    ram_addr      : OUT integer RANGE 0 TO 31;
    ram_data_in   : OUT std_logic_vector(31 DOWNTO 0);
    ram_data_out  : IN  std_logic_vector(31 DOWNTO 0)
    );
END ENTITY tracker;

ARCHITECTURE synthe_tracker OF tracker IS

  ALIAS slv IS std_logic_vector;
  ALIAS usgn IS unsigned;

  TYPE StateType IS (idle, s0, update, probe_m, done);
  SIGNAL state, nstate : StateType;

  SIGNAL top_node_size     : usgn(31 DOWNTO 0);
  SIGNAL log2top_node_size : usgn(6 DOWNTO 0);
  SIGNAL verti             : usgn(31 DOWNTO 0);

  SIGNAL rowbase      : usgn(31 DOWNTO 0);
  SIGNAL depth        : integer RANGE 0 TO 31;
  SIGNAL func_sel_i   : std_logic;
  SIGNAL group_addr_i : std_logic_vector(31 DOWNTO 0);
BEGIN

  p0 : PROCESS(state, start)
  BEGIN

    nstate   <= idle;
    done_bit <= '0';

    CASE state IS
      WHEN idle =>
        nstate <= idle;
        IF start = '1' THEN
          nstate <= s0;

        END IF;
      WHEN s0      => nstate <= s0;
      WHEN update  => nstate <= done;
      WHEN probe_m => nstate <= done;
      WHEN done =>
        nstate   <= idle;
        done_bit <= '1';
      WHEN OTHERS => NULL;
    END CASE;
    
  END PROCESS;

  p1 : PROCESS
    VARIABLE rowbase_var     : usgn(31 DOWNTO 0);
    VARIABLE local_depth_var : usgn(6 DOWNTO 0);
    VARIABLE horiz_var       : usgn(31 DOWNTO 0);

  BEGIN
    WAIT UNTIL clk'event AND clk = '1';

    state  <= nstate;
    ram_we <= '0';

    IF reset = '0' THEN                 -- active low
      state <= idle;
    ELSE
      
      IF state = idle THEN              -- initialise
        
        top_node_size     <= usgn(TOTAL_MEM_BLOCKS);
        log2top_node_size <= usgn(LOG2TMB);
        verti             <= (OTHERS => '0');
        rowbase           <= (OTHERS => '0');

      END IF;

      IF state = s0 THEN
        
        func_sel_i   <= func_sel;
        group_addr_i <= group_addr_in;


        IF to_integer(usgn(size)) <= to_integer(top_node_size SRL 4) THEN  -- size <= topsize/16
          state             <= nstate;
          verti             <= verti + 1;
          top_node_size     <= top_node_size SRL 3;
          log2top_node_size <= log2top_node_size - 3;
          rowbase           <= rowbase + (to_unsigned(1, rowbase'length) SLL (to_integer(3 * (verti - 1))));
        ELSE
          IF usgn(size) <= top_node_size SRL 3 THEN  -- size <= topsize/8
            local_depth_var := to_unsigned(3, local_depth_var'length);

          ELSIF usgn(size) <= top_node_size SRL 2 THEN  -- size <= topsize/4
            local_depth_var := to_unsigned(2, local_depth_var'length);
            
          ELSIF usgn(size) <= top_node_size SRL 1 THEN  -- size <= topsize/2 
            local_depth_var := to_unsigned(1, local_depth_var'length);
            
          ELSE                          -- size <= topsize
            local_depth_var := (OTHERS => '0');
          END IF;
          depth <= to_integer(usgn(LOG2TMB) + local_depth_var - log2top_node_size);

          IF func_sel_i = '0' THEN      -- update
            state <= update;
          ELSE                          -- make search probe
            state <= probe_m;
          END IF;
          
        END IF;
        
      END IF;  -- end s0

      IF state = update THEN
        IF flag_alloc = '1' OR (usgn(ram_data_out) > usgn(group_addr_i)) THEN
          ram_we      <= '1';
          ram_data_in <= group_addr_i;
        END IF;
      END IF;  -- end update

      IF state = probe_m THEN
        
        probe_out.verti   <= (OTHERS => '0');
        probe_out.horiz   <= (OTHERS => '0');
        probe_out.saddr   <= (OTHERS => '0');
        probe_out.nodesel <= (OTHERS => '0');
        probe_out.rowbase <= (OTHERS => '0');
        probe_out.alvec   <= '0';

        IF to_integer(usgn(ram_data_out)) > 0 THEN
          probe_out.verti   <= slv(verti);
          rowbase_var       := rowbase + (to_unsigned(1, rowbase'length) SLL (to_integer(3 * (verti - 1))));
          probe_out.horiz   <= slv(usgn(ram_data_out) - rowbase_var);
          horiz_var         := usgn(ram_data_out) - rowbase_var;
          probe_out.rowbase <= slv(rowbase);
          probe_out.nodesel <= slv(horiz_var(2 DOWNTO 0));  -- nodesel = horiz % 8             
          probe_out.saddr   <= slv(horiz_var SLL to_integer(log2top_node_size));

          probe_out.alvec <= '0';
          IF to_integer(top_node_size) = 2 THEN
            probe_out.alvec <= '1';
          END IF;
        END IF;
        
      END IF;

    END IF;  -- end reset
    
  END PROCESS;

  ram_addr <= depth;
END ARCHITECTURE;
