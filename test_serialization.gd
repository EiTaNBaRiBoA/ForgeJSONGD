extends SceneTree

func _init():
    var r = Rect2(1, 2, 3, 4)
    var json_str = JSON.stringify({"r": r})
    print("Rect2 serialization: ", json_str)

    var v = Vector2(1, 2)
    var v_str = var_to_str(v)
    print("Vector2 var_to_str: ", v_str)

    var r_str = var_to_str(r)
    print("Rect2 var_to_str: ", r_str)

    quit()
