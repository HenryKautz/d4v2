#include <iostream>
#include <fstream>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/resource.h>
#endif

#pragma once

namespace d4
{

class MemoryStat
{
 public:
  static double memUsedPeak()
  {
#ifdef __APPLE__
    // macOS has no /proc: report the peak resident set size instead (ru_maxrss
    // is in bytes on macOS).
    struct rusage ru;
    if (getrusage(RUSAGE_SELF, &ru)) return 0;
    return ru.ru_maxrss / (1024.0 * 1024.0);
#else
    // the two fields we want
    unsigned long vsize;
    long rss;
    {
      std::string ignore;
      std::ifstream ifs("/proc/self/stat", std::ios_base::in);
      ifs >> ignore >> ignore >> ignore >> ignore >>
          ignore >> ignore >> ignore >> ignore >> ignore >> ignore
          >> ignore >> ignore >> ignore >> ignore >> ignore >>
          ignore >> ignore >> ignore >> ignore >> ignore
          >> ignore >> ignore >> vsize >> rss;
    }

    return vsize / (1024.0 * 1024.0);
#endif
  } // process_mem_usage

};

}
