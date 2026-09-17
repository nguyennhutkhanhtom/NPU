"""Historical proofs for scale/baseline before repairs; not current RTL simulation."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
assigned = [i*512+j for i in range(1024) for j in range(256)]
inside = {x for x in assigned if x < 262144}
result = {
    "ternary_declared_elements":262144,
    "assignments":len(assigned),
    "out_of_bounds_assignments":sum(x>=262144 for x in assigned),
    "undriven_in_range_elements":262144-len(inside),
    "first_out_of_bounds":{"i":512,"j":0,"index":512*512},
    "first_undriven_index":256,
    "last_assigned_index":max(assigned),
    "matrix_output_row_at_lowest_lane":31,
    "matrix_input_row_at_lowest_lane":0,
    "exp_in_range_input_raw_interval":[0x8000,0x81ff],
    "exp_invalid_input_count":65536-512,
    "current_mapping_max_address":7*1024+1023,
    "literal_7d128_value":128 & ((1<<7)-1),
    "conservative_acc_width_for_512_signed_16b_ternary_terms":16+1+9,
}
assert result["out_of_bounds_assignments"]==131072
assert result["undriven_in_range_elements"]==131072
assert result["last_assigned_index"]==524031
root.joinpath("static-evidence.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
print(json.dumps(result,indent=2))
