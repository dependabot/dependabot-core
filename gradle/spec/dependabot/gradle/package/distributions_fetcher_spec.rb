# typed: false
# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require "spec_helper"
require "dependabot/gradle/package/distributions_fetcher"

RSpec.describe Dependabot::Gradle::Package::DistributionsFetcher do
  before do
    stub_request(:get, "https://services.gradle.org/versions/all")
      .to_return(
        status: 200,
        body: fixture("gradle_distributions_metadata", "versions_all.json")
      )
  end

  describe "#available_versions" do
    it {
      expect(described_class.available_versions.sort_by { |v| v[:version] }).to eq(
        [
          {
            version: "9.0.0",
            build_time: "20250731163512+0000"
          },
          {
            version: "8.14.3",
            build_time: "20250704131544+0000"
          },
          {
            version: "7.6.6",
            build_time: "20250704103426+0000"
          },
          {
            version: "8.14.2",
            build_time: "20250605133201+0000"
          },
          {
            version: "7.6.5",
            build_time: "20250604130222+0000"
          },
          {
            version: "8.14.1",
            build_time: "20250522134409+0000"
          },
          {
            version: "8.14",
            build_time: "20250425092908+0000"
          },
          {
            version: "8.13",
            build_time: "20250225092214+0000"
          },
          {
            version: "8.12.1",
            build_time: "20250124125512+0000"
          },
          {
            version: "8.12",
            build_time: "20241220154653+0000"
          },
          {
            version: "8.11.1",
            build_time: "20241120165646+0000"
          },
          {
            version: "8.11",
            build_time: "20241111135801+0000"
          },
          {
            version: "8.10.2",
            build_time: "20240923212839+0000"
          },
          {
            version: "8.10.1",
            build_time: "20240909074256+0000"
          },
          {
            version: "8.10",
            build_time: "20240814110745+0000"
          },
          {
            version: "8.9",
            build_time: "20240711143741+0000"
          },
          {
            version: "8.8",
            build_time: "20240531214656+0000"
          },
          {
            version: "8.7",
            build_time: "20240322155246+0000"
          },
          {
            version: "7.6.4",
            build_time: "20240205142918+0000"
          },
          {
            version: "8.6",
            build_time: "20240202164716+0000"
          },
          {
            version: "8.5",
            build_time: "20231129140857+0000"
          },
          {
            version: "8.4",
            build_time: "20231004205213+0000"
          },
          {
            version: "7.6.3",
            build_time: "20231004155947+0000"
          },
          {
            version: "8.3",
            build_time: "20230817070647+0000"
          },
          {
            version: "8.2.1",
            build_time: "20230710121235+0000"
          },
          {
            version: "8.2",
            build_time: "20230630180230+0000"
          },
          {
            version: "7.6.2",
            build_time: "20230630154251+0000"
          },
          {
            version: "8.1.1",
            build_time: "20230421123126+0000"
          },
          {
            version: "8.1",
            build_time: "20230412120745+0000"
          },
          {
            version: "8.0.2",
            build_time: "20230303164137+0000"
          },
          {
            version: "7.6.1",
            build_time: "20230224135442+0000"
          },
          {
            version: "6.9.4",
            build_time: "20230222084312+0000"
          },
          {
            version: "8.0.1",
            build_time: "20230217200948+0000"
          },
          {
            version: "8.0",
            build_time: "20230213131521+0000"
          },
          {
            version: "7.6",
            build_time: "20221125133510+0000"
          },
          {
            version: "6.9.3",
            build_time: "20221017074402+0000"
          },
          {
            version: "7.5.1",
            build_time: "20220805211756+0000"
          },
          {
            version: "7.5",
            build_time: "20220714124815+0000"
          },
          {
            version: "7.4.2",
            build_time: "20220331152529+0000"
          },
          {
            version: "7.4.1",
            build_time: "20220309150447+0000"
          },
          {
            version: "7.4",
            build_time: "20220208095838+0000"
          },
          {
            version: "7.3.3",
            build_time: "20211222123754+0000"
          },
          {
            version: "6.9.2",
            build_time: "20211221172537+0000"
          },
          {
            version: "7.3.2",
            build_time: "20211215112231+0000"
          },
          {
            version: "7.3.1",
            build_time: "20211201154220+0000"
          },
          {
            version: "7.3",
            build_time: "20211109204036+0000"
          },
          {
            version: "6.9.1",
            build_time: "20210820111518+0000"
          },
          {
            version: "7.2",
            build_time: "20210817095903+0000"
          },
          {
            version: "7.1.1",
            build_time: "20210702121643+0000"
          },
          {
            version: "7.1",
            build_time: "20210614144726+0000"
          },
          {
            version: "7.0.2",
            build_time: "20210514120231+0000"
          },
          {
            version: "7.0.1",
            build_time: "20210510160858+0000"
          },
          {
            version: "6.9",
            build_time: "20210507072853+0000"
          },
          {
            version: "7.0",
            build_time: "20210409222731+0000"
          },
          {
            version: "6.8.3",
            build_time: "20210222161328+0000"
          },
          {
            version: "6.8.2",
            build_time: "20210205125300+0000"
          },
          {
            version: "6.8.1",
            build_time: "20210122132008+0000"
          },
          {
            version: "6.8",
            build_time: "20210108163846+0000"
          },
          {
            version: "6.7.1",
            build_time: "20201116170924+0000"
          },
          {
            version: "6.7",
            build_time: "20201014161312+0000"
          },
          {
            version: "6.6.1",
            build_time: "20200825162912+0000"
          },
          {
            version: "6.6",
            build_time: "20200810220619+0000"
          },
          {
            version: "6.5.1",
            build_time: "20200630063247+0000"
          },
          {
            version: "6.5",
            build_time: "20200602204621+0000"
          },
          {
            version: "6.4.1",
            build_time: "20200515194340+0000"
          },
          {
            version: "6.4",
            build_time: "20200505191855+0000"
          },
          {
            version: "6.3",
            build_time: "20200324195207+0000"
          },
          {
            version: "6.2.2",
            build_time: "20200304084931+0000"
          },
          {
            version: "6.2.1",
            build_time: "20200224202410+0000"
          },
          {
            version: "6.2",
            build_time: "20200217083201+0000"
          },
          {
            version: "6.1.1",
            build_time: "20200124223024+0000"
          },
          {
            version: "6.1",
            build_time: "20200115235646+0000"
          },
          {
            version: "6.0.1",
            build_time: "20191118202501+0000"
          },
          {
            version: "6.0",
            build_time: "20191108181212+0000"
          },
          {
            version: "5.6.4",
            build_time: "20191101204200+0000"
          },
          {
            version: "5.6.3",
            build_time: "20191018002836+0000"
          },
          {
            version: "5.6.2",
            build_time: "20190905161354+0000"
          },
          {
            version: "5.6.1",
            build_time: "20190828024934+0000"
          },
          {
            version: "5.6",
            build_time: "20190814210525+0000"
          },
          {
            version: "5.5.1",
            build_time: "20190710203812+0000"
          },
          {
            version: "5.5",
            build_time: "20190628173605+0000"
          },
          {
            version: "5.4.1",
            build_time: "20190426081442+0000"
          },
          {
            version: "5.4",
            build_time: "20190416024416+0000"
          },
          {
            version: "5.3.1",
            build_time: "20190328090923+0000"
          },
          {
            version: "5.3",
            build_time: "20190320110329+0000"
          },
          {
            version: "5.2.1",
            build_time: "20190208190010+0000"
          },
          {
            version: "5.2",
            build_time: "20190204111648+0000"
          },
          {
            version: "5.1.1",
            build_time: "20190110230502+0000"
          },
          {
            version: "5.1",
            build_time: "20190102185747+0000"
          },
          {
            version: "4.10.3",
            build_time: "20181205005054+0000"
          },
          {
            version: "5.0",
            build_time: "20181126114843+0000"
          },
          {
            version: "4.10.2",
            build_time: "20180919181015+0000"
          },
          {
            version: "4.10.1",
            build_time: "20180912113327+0000"
          },
          {
            version: "4.10",
            build_time: "20180827183506+0000"
          },
          {
            version: "4.9",
            build_time: "20180716081403+0000"
          },
          {
            version: "4.8.1",
            build_time: "20180621075306+0000"
          },
          {
            version: "4.8",
            build_time: "20180604103958+0000"
          },
          {
            version: "4.7",
            build_time: "20180418090912+0000"
          },
          {
            version: "4.6",
            build_time: "20180228133636+0000"
          },
          {
            version: "4.5.1",
            build_time: "20180205132249+0000"
          },
          {
            version: "4.5",
            build_time: "20180124170452+0000"
          },
          {
            version: "4.4.1",
            build_time: "20171220154523+0000"
          },
          {
            version: "4.4",
            build_time: "20171206090506+0000"
          },
          {
            version: "4.3.1",
            build_time: "20171108085945+0000"
          },
          {
            version: "4.3",
            build_time: "20171030154329+0000"
          },
          {
            version: "4.2.1",
            build_time: "20171002153621+0000"
          },
          {
            version: "4.2",
            build_time: "20170920144823+0000"
          },
          {
            version: "4.1",
            build_time: "20170807143848+0000"
          },
          {
            version: "4.0.2",
            build_time: "20170726161918+0000"
          },
          {
            version: "4.0.1",
            build_time: "20170707140241+0000"
          },
          {
            version: "3.5.1",
            build_time: "20170616143627+0000"
          },
          {
            version: "4.0",
            build_time: "20170614151108+0000"
          },
          {
            version: "3.5",
            build_time: "20170410133725+0000"
          },
          {
            version: "3.4.1",
            build_time: "20170303194541+0000"
          },
          {
            version: "3.4",
            build_time: "20170220144926+0000"
          },
          {
            version: "3.3",
            build_time: "20170103153104+0000"
          },
          {
            version: "3.2.1",
            build_time: "20161122151954+0000"
          },
          {
            version: "3.2",
            build_time: "20161114123259+0000"
          },
          {
            version: "3.1",
            build_time: "20160919105353+0000"
          },
          {
            version: "3.0",
            build_time: "20160815131501+0000"
          },
          {
            version: "2.14.1",
            build_time: "20160718063837+0000"
          },
          {
            version: "2.14",
            build_time: "20160614071637+0000"
          },
          {
            version: "2.13",
            build_time: "20160425041010+0000"
          },
          {
            version: "2.12",
            build_time: "20160314083203+0000"
          },
          {
            version: "2.11",
            build_time: "20160208075916+0000"
          },
          {
            version: "2.10",
            build_time: "20151221211504+0000"
          },
          {
            version: "2.9",
            build_time: "20151117070217+0000"
          },
          {
            version: "2.8",
            build_time: "20151020034636+0000"
          },
          {
            version: "2.7",
            build_time: "20150914072616+0000"
          },
          {
            version: "2.6",
            build_time: "20150810131506+0000"
          },
          {
            version: "2.5",
            build_time: "20150708073837+0000"
          },
          {
            version: "2.4",
            build_time: "20150505080924+0000"
          },
          {
            version: "2.3",
            build_time: "20150216050933+0000"
          },
          {
            version: "2.2.1",
            build_time: "20141124094535+0000"
          },
          {
            version: "2.2",
            build_time: "20141110133144+0000"
          },
          {
            version: "2.1",
            build_time: "20140908104039+0000"
          },
          {
            version: "2.0",
            build_time: "20140701074534+0000"
          },
          {
            version: "1.12",
            build_time: "20140429092431+0000"
          },
          {
            version: "1.11",
            build_time: "20140211113439+0000"
          },
          {
            version: "1.10",
            build_time: "20131217092815+0000"
          },
          {
            version: "1.9",
            build_time: "20131119082002+0000"
          },
          {
            version: "1.8",
            build_time: "20130924073233+0000"
          },
          {
            version: "1.7",
            build_time: "20130806111956+0000"
          },
          {
            version: "1.6",
            build_time: "20130507091214+0000"
          },
          {
            version: "1.5",
            build_time: "20130327140935+0000"
          },
          {
            version: "1.4",
            build_time: "20130128034246+0000"
          },
          {
            version: "1.3",
            build_time: "20121120113738+0000"
          },
          {
            version: "1.2",
            build_time: "20120912104602+0000"
          },
          {
            version: "1.1",
            build_time: "20120731132432+0000"
          },
          {
            version: "1.0",
            build_time: "20120612025621+0200"
          },
          {
            version: "0.9.2",
            build_time: "20110123133421+1100"
          },
          {
            version: "0.9.1",
            build_time: "20110102114057+1100"
          },
          {
            version: "0.9",
            build_time: "20101219125006+1100"
          },
          {
            version: "0.8",
            build_time: "20090928140159+0200"
          },
          {
            version: "0.7",
            build_time: "20090720085013+0200"
          }
        ].sort_by { |v| v[:version] }
      )
    }
  end
end

# rubocop:enable RSpec/ExampleLength
