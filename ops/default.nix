{ buildGoModule, fetchFromGitHub, lib }:
buildGoModule rec {
  pname = "ops";
  version = "0.1.15";

  src = fetchFromGitHub {
    owner = "nanovms";
    repo = "ops";
    rev = "${version}";
    sha256 = "043rb3b92nppxs87lifd94z8zsc29xi9q3vncj982f3p1p918biz";
  };

  vendorSha256 = "02cdmxmp8kk9fbk2gyqrmn4b6x2fgqjqwqd6j45r4fk61zc0jn3j";

  # Tests fail with:
  #  version lookup failed, using local.
  #  No local build found.
  #  FAIL       github.com/nanovms/ops/cmd
  doCheck = false;

  meta = with lib; {
    description = "Ops is a tool for creating and running a Nanos unikernel";
    homepage = "https://github.com/nanovms/ops";
    license = licenses.mit;
    maintainers = with maintainers; [ matejc ];
    platforms = platforms.linux;
  };
}
