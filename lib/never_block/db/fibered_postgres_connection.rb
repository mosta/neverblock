require 'pg'

module NeverBlock

  module DB
    # A modified postgres connection driver
    # builds on the original pg driver.
    # This driver is able to register the socket
    # at a certain backend (EM or Rev)
    # and then whenever the query is executed
    # within the scope of a friendly fiber
    # it will be done in async mode and the fiber
    # will yield
	  class FiberedPostgresConnection < PGconn	      
      # needed to access the sockect by the event loop
      attr_reader :fd, :io
        
      # Creates a new postgresql connection, sets it
      # to nonblocking and wraps the descriptor in an IO
      # object.
	    def initialize(*args)
        super(*args)
        @fd = socket
        @io = IO.new(socket)
        #setnonblocking(true)
      end
        
      # Assuming the use of NeverBlock fiber extensions and that the exec is run in
      # the context of a fiber. One that have the value :neverblock set to true.
      # All neverblock IO classes check this value, setting it to false will force
      # the execution in a blocking way.
      def exec(sql)
        if Fiber.respond_to? :current and Fiber.current[:neverblock]		      
          self.send_query sql
          @fiber = Fiber.current		      
          Fiber.yield 
        else		      
          super(sql)
        end		
      end
      
      # Attaches the connection socket to an event loop.
      # Currently only supports EM, but Rev support will be
      # completed soon.
      def register_with_event_loop(loop)
        if loop == :em
          unless EM.respond_to?(:attach)
            puts "invalide EM version, please download the modified gem from: (http://github.com/riham/eventmachine)"
            exit
          end
          if EM.reactor_running?
             @em_connection = EM::attach(@io,EMConnectionHandler,self)
          else
            raise "REACTOR NOT RUNNING YA ZALAMA"
          end 
        elsif loop.class.name == "REV::Loop"
          loop.attach(RevConnectionHandler.new(socket))
        else
          raise "could not register with the event loop"
        end
        @loop = loop
      end

      # Unattaches the connection socket from the event loop
      # As with register, EM is the only one supported for now
      def unregister_from_event_loop
        if @loop == :em
          @em_connection.unattach(false)
        else
          raise NotImplementedError.new("unregister_from_event_loop not implemented for #{@loop}")
        end
      end

      # The callback, this is called whenever
      # there is data available at the socket
      def process_command
        # make sure all commands are sent
        # before attempting to read
        #return unless self.flush
        self.consume_input
        unless is_busy		
          res, data = 0, []
          while res != nil
            res = self.get_result
            data << res unless res.nil?
          end
          #let the fiber continue its work		      
          @fiber.resume(data.last)
        end
      end
      
    end #FiberedPostgresConnection 
    
    # A connection handler for EM
    # More to follow.
    module EMConnectionHandler
      def initialize connection
        @connection = connection
      end
      def notify_readable
        @connection.process_command
      end
    end

    end #DB

end #NeverBlock

NeverBlock::DB::FPGconn = NeverBlock::DB::FiberedPostgresConnection
