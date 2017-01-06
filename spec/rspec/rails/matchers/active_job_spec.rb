require "spec_helper"
require "rspec/rails/feature_check"

if RSpec::Rails::FeatureCheck.has_active_job?
  require "rspec/rails/matchers/active_job"

  class GlobalIdModel
    include GlobalID::Identification

    attr_reader :id

    def self.find(id)
      new(id)
    end

    def initialize(id)
      @id = id
    end

    def ==(comparison_object)
      id == comparison_object.id
    end

    def to_global_id(options = {})
      @global_id ||= GlobalID.create(self, :app => "rspec-suite")
    end
  end
end

RSpec.describe "ActiveJob matchers", :skip => !RSpec::Rails::FeatureCheck.has_active_job? do
  include RSpec::Rails::Matchers
  include ActiveJob::TestHelper

  around do |example|
    original_logger = ActiveJob::Base.logger
    ActiveJob::Base.logger = Logger.new(nil) # Silence messages "[ActiveJob] Enqueued ...".
    example.run
    ActiveJob::Base.logger = original_logger
  end

  let(:heavy_lifting_job) do
    Class.new(ActiveJob::Base) do
      def perform; end
    end
  end

  let(:hello_job) do
    Class.new(ActiveJob::Base) do
      def perform(*)
      end
    end
  end

  let(:logging_job) do
    Class.new(ActiveJob::Base) do
      def perform; end
    end
  end

  before do
    ActiveJob::Base.queue_adapter = :test

    stub_const('::Example::HeavyLiftingJob', heavy_lifting_job)
    stub_const('::Example::HelloJob', hello_job)
    stub_const('::Example::LogginJob', logging_job)
  end

  describe "have_enqueued_job" do
    it "raises ArgumentError when no Proc passed to expect" do
      expect {
        expect(heavy_lifting_job.perform_later).to have_enqueued_job
      }.to raise_error(ArgumentError)
    end

    it "passes with default jobs count (exactly one)" do
      expect {
        heavy_lifting_job.perform_later
      }.to have_enqueued_job
    end

    it "passes when using alias" do
      expect {
        heavy_lifting_job.perform_later
      }.to enqueue_job
    end

    it "counts only jobs enqueued in block" do
      heavy_lifting_job.perform_later
      expect {
        heavy_lifting_job.perform_later
      }.to have_enqueued_job.exactly(1)
    end

    it "passes when negated" do
      expect { }.not_to have_enqueued_job
    end

    it "fails when job is not enqueued" do
      expect {
        expect { }.to have_enqueued_job
      }.to raise_error(/expected to enqueue exactly 1 jobs, but enqueued 0/)
    end

    it "fails when too many jobs enqueued" do
      expect {
        expect {
          heavy_lifting_job.perform_later
          heavy_lifting_job.perform_later
        }.to have_enqueued_job.exactly(1)
      }.to raise_error(/expected to enqueue exactly 1 jobs, but enqueued 2/)
    end

    it "reports correct number in fail error message" do
      heavy_lifting_job.perform_later
      expect {
        expect { }.to have_enqueued_job.exactly(1)
      }.to raise_error(/expected to enqueue exactly 1 jobs, but enqueued 0/)
    end

    it "fails when negated and job is enqueued" do
      expect {
        expect { heavy_lifting_job.perform_later }.not_to have_enqueued_job
      }.to raise_error(/expected not to enqueue exactly 1 jobs, but enqueued 1/)
    end

    it "passes with job name" do
      expect {
        hello_job.perform_later
        heavy_lifting_job.perform_later
      }.to have_enqueued_job(hello_job).exactly(1).times
    end

    it "passes with multiple jobs" do
      expect {
        hello_job.perform_later
        logging_job.perform_later
        heavy_lifting_job.perform_later
      }.to have_enqueued_job(hello_job).and have_enqueued_job(logging_job)
    end

    it "passes with :once count" do
      expect {
        hello_job.perform_later
      }.to have_enqueued_job.exactly(:once)
    end

    it "passes with :twice count" do
      expect {
        hello_job.perform_later
        hello_job.perform_later
      }.to have_enqueued_job.exactly(:twice)
    end

    it "passes with :thrice count" do
      expect {
        hello_job.perform_later
        hello_job.perform_later
        hello_job.perform_later
      }.to have_enqueued_job.exactly(:thrice)
    end

    it "passes with at_least count when enqueued jobs are over limit" do
      expect {
        hello_job.perform_later
        hello_job.perform_later
      }.to have_enqueued_job.at_least(:once)
    end

    it "passes with at_most count when enqueued jobs are under limit" do
      expect {
        hello_job.perform_later
      }.to have_enqueued_job.at_most(:once)
    end

    it "generates failure message with at least hint" do
      expect {
        expect { }.to have_enqueued_job.at_least(:once)
      }.to raise_error(/expected to enqueue at least 1 jobs, but enqueued 0/)
    end

    it "generates failure message with at most hint" do
      expect {
        expect {
          hello_job.perform_later
          hello_job.perform_later
        }.to have_enqueued_job.at_most(:once)
      }.to raise_error(/expected to enqueue at most 1 jobs, but enqueued 2/)
    end

    it "passes with provided queue name" do
      expect {
        hello_job.set(:queue => "low").perform_later
      }.to have_enqueued_job.on_queue("low")
    end

    it "passes with provided at date" do
      date = Date.tomorrow.noon
      expect {
        hello_job.set(:wait_until => date).perform_later
      }.to have_enqueued_job.at(date)
    end

    it "passes with provided arguments" do
      expect {
        hello_job.perform_later(42, "David")
      }.to have_enqueued_job.with(42, "David")
    end

    it "passes with provided arguments containing global id object" do
      global_id_object = GlobalIdModel.new("42")

      expect {
        hello_job.perform_later(global_id_object)
      }.to have_enqueued_job.with(global_id_object)
    end

    it "passes with provided argument matchers" do
      expect {
        hello_job.perform_later(42, "David")
      }.to have_enqueued_job.with(instance_of(Fixnum), instance_of(String))
    end

    it "generates failure message with all provided options" do
      date = Date.tomorrow.noon
      message = "expected to enqueue exactly 2 jobs, with [42], on queue low, at #{date}, but enqueued 0" + \
                "\nEnqueued jobs:" + \
                "\n  Class job with [1], on queue default"

      expect {
        expect {
          hello_job.perform_later(1)
        }.to have_enqueued_job(hello_job).with(42).on_queue("low").at(date).exactly(2).times
      }.to raise_error(message)
    end

    it "throws descriptive error when no test adapter set" do
      queue_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :inline

      expect {
        expect { heavy_lifting_job.perform_later }.to have_enqueued_job
      }.to raise_error("To use ActiveJob matchers set `ActiveJob::Base.queue_adapter = :test`")

      ActiveJob::Base.queue_adapter = queue_adapter
    end

    it "fails with with block with incorrect data" do
      expect {
        expect {
          hello_job.perform_later("asdf")
        }.to have_enqueued_job(hello_job).with { |arg|
          expect(arg).to eq("zxcv")
        }
      }.to raise_error { |e|
        expect(e.message).to match(/expected: "zxcv"/)
        expect(e.message).to match(/got: "asdf"/)
      }
    end

    it "passes multiple arguments to with block" do
      expect {
        hello_job.perform_later("asdf", "zxcv")
      }.to have_enqueued_job(hello_job).with { |first_arg, second_arg|
        expect(first_arg).to eq("asdf")
        expect(second_arg).to eq("zxcv")
      }
    end

    it "passess deserialized arguments to with block" do
      global_id_object = GlobalIdModel.new("42")

      expect {
        hello_job.perform_later(global_id_object, :symbolized_key => "asdf")
      }.to have_enqueued_job(hello_job).with { |first_arg, second_arg|
        expect(first_arg).to eq(global_id_object)
        expect(second_arg).to eq({:symbolized_key => "asdf"})
      }
    end

    it "only calls with block if other conditions are met" do
      noon = Date.tomorrow.noon
      midnight = Date.tomorrow.midnight
      expect {
        hello_job.set(:wait_until => noon).perform_later("asdf")
        hello_job.set(:wait_until => midnight).perform_later("zxcv")
      }.to have_enqueued_job(hello_job).at(noon).with { |arg|
        expect(arg).to eq("asdf")
      }
    end
  end

  describe "have_been_enqueued" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    it "passes with default jobs count (exactly one)" do
      heavy_lifting_job.perform_later
      expect(heavy_lifting_job).to have_been_enqueued
    end

    it "counts all enqueued jobs" do
      heavy_lifting_job.perform_later
      heavy_lifting_job.perform_later
      expect(heavy_lifting_job).to have_been_enqueued.exactly(2)
    end

    it "passes when negated" do
      expect(heavy_lifting_job).not_to have_been_enqueued
    end

    it "fails when job is not enqueued" do
      expect {
        expect(heavy_lifting_job).to have_been_enqueued
      }.to raise_error(/expected to enqueue exactly 1 jobs, but enqueued 0/)
    end
  end

  describe "have_performed_job" do
    it "raises ArgumentError when no Proc passed to expect" do
      perform_enqueued_jobs {
        expect {
          expect(heavy_lifting_job.perform_later).to have_performed_job
        }.to raise_error(ArgumentError)
      }
    end

    it "passes with default jobs count (exactly one)" do
      perform_enqueued_jobs {
        expect {
          heavy_lifting_job.perform_later
        }.to have_performed_job
      }
    end

    it "passes when using alias" do
      perform_enqueued_jobs {
        expect {
          heavy_lifting_job.perform_later
        }.to perform_job
      }
    end

    it "counts only jobs performed in block" do
      perform_enqueued_jobs {
        heavy_lifting_job.perform_later
        expect {
          heavy_lifting_job.perform_later
        }.to have_performed_job.exactly(1)
      }
    end

    it "passes when negated" do
      expect { }.not_to have_performed_job
    end

    it "fails when job is not performed" do
      expect {
        expect { }.to have_performed_job
      }.to raise_error(/expected to perform exactly 1 jobs, but performed 0/)
    end

    it "fails when too many jobs performed" do
      perform_enqueued_jobs {
        expect {
          expect {
            heavy_lifting_job.perform_later
            heavy_lifting_job.perform_later
          }.to have_performed_job.exactly(1)
        }.to raise_error(/expected to perform exactly 1 jobs, but performed 2/)
      }
    end

    it "reports correct number in fail error message" do
      heavy_lifting_job.perform_later
      expect {
        expect { }.to have_performed_job.exactly(1)
      }.to raise_error(/expected to perform exactly 1 jobs, but performed 0/)
    end

    it "fails when negated and job is performed" do
      perform_enqueued_jobs {
        expect {
          expect { heavy_lifting_job.perform_later }.not_to have_performed_job
        }.to raise_error(/expected not to perform exactly 1 jobs, but performed 1/)
      }
    end

    it "passes with job name" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later
          heavy_lifting_job.perform_later
        }.to have_performed_job(hello_job).exactly(1).times
      }
    end

    it "passes with multiple jobs" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later
          logging_job.perform_later
          heavy_lifting_job.perform_later
        }.to have_performed_job(hello_job).and have_performed_job(logging_job)
      }
    end

    it "passes with :once count" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later
        }.to have_performed_job.exactly(:once)
      }
    end

    it "passes with :twice count" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later
          hello_job.perform_later
        }.to have_performed_job.exactly(:twice)
      }
    end

    it "passes with :thrice count" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later
          hello_job.perform_later
          hello_job.perform_later
        }.to have_performed_job.exactly(:thrice)
      }
    end

    it "passes with at_least count when performed jobs are over limit" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later
          hello_job.perform_later
        }.to have_performed_job.at_least(:once)
      }
    end

    it "passes with at_most count when performed jobs are under limit" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later
        }.to have_performed_job.at_most(:once)
      }
    end

    it "generates failure message with at least hint" do
      expect {
        expect { }.to have_performed_job.at_least(:once)
      }.to raise_error(/expected to perform at least 1 jobs, but performed 0/)
    end

    it "generates failure message with at most hint" do
      perform_enqueued_jobs {
        expect {
          expect {
            hello_job.perform_later
            hello_job.perform_later
          }.to have_performed_job.at_most(:once)
        }.to raise_error(/expected to perform at most 1 jobs, but performed 2/)
      }
    end

    it "passes with provided queue name" do
      perform_enqueued_jobs {
        expect {
          hello_job.set(:queue => "low").perform_later
        }.to have_performed_job.on_queue("low")
      }
    end

    it "passes with provided at date" do
      date = Date.tomorrow.noon
      perform_enqueued_jobs {
        expect {
          hello_job.set(:wait_until => date).perform_later
        }.to have_performed_job.at(date)
      }
    end

    it "passes with provided arguments" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later(42, "David")
        }.to have_performed_job.with(42, "David")
      }
    end

    it "passes with provided arguments containing global id object" do
      global_id_object = GlobalIdModel.new("42")

      perform_enqueued_jobs {
        expect {
          hello_job.perform_later(global_id_object)
        }.to have_performed_job.with(global_id_object)
      }
    end

    it "passes with provided argument matchers" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later(42, "David")
        }.to have_performed_job.with(instance_of(Fixnum), instance_of(String))
      }
    end

    it "generates failure message with all provided options" do
      date = Date.tomorrow.noon
      message = "expected to perform exactly 2 jobs, with [42], on queue low, at #{date}, but performed 0" + \
                "\nPerformed jobs:" + \
                "\n  Class job with [1], on queue default"

      perform_enqueued_jobs {
        expect {
          expect {
            hello_job.perform_later(1)
          }.to have_performed_job(hello_job).with(42).on_queue("low").at(date).exactly(2).times
        }.to raise_error(message)
      }
    end

    it "throws descriptive error when no test adapter set" do
      queue_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :inline

      expect {
        expect { heavy_lifting_job.perform_later }.to have_performed_job
      }.to raise_error("To use ActiveJob matchers set `ActiveJob::Base.queue_adapter = :test`")

      ActiveJob::Base.queue_adapter = queue_adapter
    end

    it "fails with with block with incorrect data" do
      perform_enqueued_jobs {
        expect {
          expect {
            hello_job.perform_later("asdf")
          }.to have_performed_job(hello_job).with { |arg|
            expect(arg).to eq("zxcv")
          }
        }.to raise_error { |e|
          expect(e.message).to match(/expected: "zxcv"/)
          expect(e.message).to match(/got: "asdf"/)
        }
      }
    end

    it "passes multiple arguments to with block" do
      perform_enqueued_jobs {
        expect {
          hello_job.perform_later("asdf", "zxcv")
        }.to have_performed_job(hello_job).with { |first_arg, second_arg|
          expect(first_arg).to eq("asdf")
          expect(second_arg).to eq("zxcv")
        }
      }
    end

    it "passess deserialized arguments to with block" do
      global_id_object = GlobalIdModel.new("42")

      perform_enqueued_jobs {
        expect {
          hello_job.perform_later(global_id_object, :symbolized_key => "asdf")
        }.to have_performed_job(hello_job).with { |first_arg, second_arg|
          expect(first_arg).to eq(global_id_object)
          expect(second_arg).to eq({:symbolized_key => "asdf"})
        }
      }
    end

    it "only calls with block if other conditions are met" do
      noon = Date.tomorrow.noon
      midnight = Date.tomorrow.midnight

      perform_enqueued_jobs {
        expect {
          hello_job.set(:wait_until => noon).perform_later("asdf")
          hello_job.set(:wait_until => midnight).perform_later("zxcv")
        }.to have_performed_job(hello_job).at(noon).with { |arg|
          expect(arg).to eq("asdf")
        }
      }
    end

    it "fails when job is just enqueued" do
      heavy_lifting_job.perform_later
      expect {
        expect {
          heavy_lifting_job.perform_later
        }.to have_performed_job(heavy_lifting_job)
      }.to raise_error(/expected to perform exactly 1 jobs, but performed 0/)
    end
  end

  describe "have_been_performed" do
    before { ActiveJob::Base.queue_adapter.performed_jobs.clear }

    it "passes with default jobs count (exactly one)" do
      perform_enqueued_jobs {
        heavy_lifting_job.perform_later
      }
      expect(heavy_lifting_job).to have_been_performed
    end

    it "counts all performed jobs" do
      perform_enqueued_jobs {
        heavy_lifting_job.perform_later
        heavy_lifting_job.perform_later
      }
      expect(heavy_lifting_job).to have_been_performed.exactly(2)
    end

    it "passes when negated" do
      expect(heavy_lifting_job).not_to have_been_performed
    end

    it "fails when job is not performed" do
      expect {
        expect(heavy_lifting_job).to have_been_performed
      }.to raise_error(/expected to perform exactly 1 jobs, but performed 0/)
    end

    it "fails when job is just enqueued" do
      heavy_lifting_job.perform_later
      expect {
        expect(heavy_lifting_job).to have_been_performed
      }.to raise_error(/expected to perform exactly 1 jobs, but performed 0/)
    end
  end
end
