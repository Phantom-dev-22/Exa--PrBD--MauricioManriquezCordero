--REQUERIMIENTO 1:

-- Habilitación de mensajes
SET SERVEROUTPUT ON;

-- Creación de secuencia para los errores
CREATE SEQUENCE ERRORES_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;

-- Función FN_PROMEDIO_ALUMNO
CREATE OR REPLACE FUNCTION FN_PROMEDIO_ALUMNO (
    p_cod_alumno IN NUMBER,
    p_cod_asignatura IN NUMBER
) RETURN NUMBER IS
    v_promedio NUMBER;
BEGIN
    -- Calcular promedio de notas
    SELECT ROUND((NVL(NOTA1, 0) + NVL(NOTA2, 0) + NVL(NOTA3, 0) + NVL(NOTA4, 0) + NVL(NOTA5, 0)) / 5, 2)
    INTO v_promedio
    FROM NOTA_ALUMNO
    WHERE COD_ALUMNO = p_cod_alumno AND COD_ASIGNATURA = p_cod_asignatura;

    RETURN v_promedio;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('No se encontraron notas para el alumno ' || p_cod_alumno || ' y asignatura ' || p_cod_asignatura);
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE;
END FN_PROMEDIO_ALUMNO;
/

-- Procedimiento SP_PROCESAR_ALUMNOS
CREATE OR REPLACE PROCEDURE SP_PROCESAR_ALUMNOS IS
    -- Declaraciones
    CURSOR cur_alumnos IS
        SELECT COD_ALUMNO, COD_ASIGNATURA FROM NOTA_ALUMNO;

    v_promedio NUMBER;
    v_situacion_asig VARCHAR2(10);
BEGIN
    -- Recorremos cada alumno y asignatura
    FOR reg IN cur_alumnos LOOP
        BEGIN
            DBMS_OUTPUT.PUT_LINE('Procesando alumno: ' || reg.COD_ALUMNO || ', asignatura: ' || reg.COD_ASIGNATURA);

            -- Calcular promedio usando la función
            v_promedio := FN_PROMEDIO_ALUMNO(reg.COD_ALUMNO, reg.COD_ASIGNATURA);

            -- Verificar si el promedio es válido
            IF v_promedio IS NOT NULL THEN
                -- Determinar situación del alumno
                IF v_promedio >= 4.0 THEN
                    v_situacion_asig := 'A';
                ELSE
                    v_situacion_asig := 'R';
                END IF;

                -- Insertar en la tabla PROMEDIO_ASIG_ALUMNO
                INSERT INTO PROMEDIO_ASIG_ALUMNO (COD_ALUMNO, COD_ASIGNATURA, PROMEDIO_ASIG, SITUACION_ASIG)
                VALUES (reg.COD_ALUMNO, reg.COD_ASIGNATURA, v_promedio, v_situacion_asig);

                DBMS_OUTPUT.PUT_LINE('Promedio insertado: ' || v_promedio || ', situación: ' || v_situacion_asig);

                -- Actualizar la tabla RESUMEN_SITUACION_ASIG
                IF v_promedio >= 4.0 THEN
                    UPDATE RESUMEN_SITUACION_ASIG
                    SET TOTAL_APROB = TOTAL_APROB + 1
                    WHERE COD_ASIGNATURA = reg.COD_ASIGNATURA;

                    DBMS_OUTPUT.PUT_LINE('Asignatura aprobada actualizada para: ' || reg.COD_ASIGNATURA);
                ELSE
                    UPDATE RESUMEN_SITUACION_ASIG
                    SET TOTAL_REPROB = TOTAL_REPROB + 1
                    WHERE COD_ASIGNATURA = reg.COD_ASIGNATURA;

                    DBMS_OUTPUT.PUT_LINE('Asignatura reprobada actualizada para: ' || reg.COD_ASIGNATURA);
                END IF;
            ELSE
                DBMS_OUTPUT.PUT_LINE('Promedio no calculado para alumno ' || reg.COD_ALUMNO || ' y asignatura ' || reg.COD_ASIGNATURA);
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                -- Registrar error
                DECLARE
                    v_error_msg VARCHAR2(4000);
                BEGIN
                    v_error_msg := SQLERRM;
                    INSERT INTO ERRORES (ID_ERROR, SUBPROGRAMA_ERROR, DESCRIPCION_ERROR)
                    VALUES (ERRORES_SEQ.NEXTVAL, 'SP_PROCESAR_ALUMNOS', v_error_msg);

                    DBMS_OUTPUT.PUT_LINE('Error procesando alumno ' || reg.COD_ALUMNO || ': ' || v_error_msg);
                END;
        END;
    END LOOP;

    -- Confirmar cambios
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Proceso completado.');
END SP_PROCESAR_ALUMNOS;
/

-- Trigger TRG_MANEJO_ERRORES
CREATE OR REPLACE TRIGGER TRG_MANEJO_ERRORES
AFTER INSERT OR UPDATE OR DELETE ON PROMEDIO_ASIG_ALUMNO
FOR EACH ROW
DECLARE
    v_error_msg VARCHAR2(4000);
BEGIN
    IF INSERTING THEN
        DBMS_OUTPUT.PUT_LINE('Se insertó un promedio para el alumno ' || :NEW.COD_ALUMNO);
    ELSIF UPDATING THEN
        DBMS_OUTPUT.PUT_LINE('Se actualizó un promedio para el alumno ' || :OLD.COD_ALUMNO);
    ELSIF DELETING THEN
        DBMS_OUTPUT.PUT_LINE('Se eliminó un promedio para el alumno ' || :OLD.COD_ALUMNO);
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := SQLERRM;
        INSERT INTO ERRORES (ID_ERROR, SUBPROGRAMA_ERROR, DESCRIPCION_ERROR)
        VALUES (ERRORES_SEQ.NEXTVAL, 'TRG_MANEJO_ERRORES', v_error_msg);

        DBMS_OUTPUT.PUT_LINE('Error en el trigger: ' || v_error_msg);
END;
/

-- Ejecutar el procedimiento
BEGIN
    SP_PROCESAR_ALUMNOS;
END;
/

COMMIT;


--REQUERIMIENTO 2:

CREATE OR REPLACE TRIGGER ALUMNO_JORNADA
BEFORE INSERT OR UPDATE OR DELETE ON ALUMNO
FOR EACH ROW
DECLARE
    V_DIA  NUMBER;  -- Día de la semana
    V_HORA NUMBER;  -- Hora en formato 24 horas
BEGIN
    V_DIA := TO_NUMBER(TO_CHAR(SYSDATE, 'D'));  -- Obtiene el día (1=Domingo, 2=Lunes, ..., 7=Sábado)
    V_HORA := TO_NUMBER(TO_CHAR(SYSDATE, 'HH24'));  -- Obtiene la hora en formato 24h

    -- Verifica si la operación ocurre en días laborales (lunes a viernes) y horario permitido
    IF (V_DIA BETWEEN 2 AND 6) AND (V_HORA BETWEEN 8 AND 18) THEN
        NULL;  -- Permitir la operación
    ELSE
        -- Si la operación ocurre fuera del horario permitido
        IF INSERTING THEN
            RAISE_APPLICATION_ERROR(-20501, 'SE DEBE INSERTAR VALORES SOLO EN LA JORNADA DE TRABAJO');
        ELSIF UPDATING THEN
            RAISE_APPLICATION_ERROR(-20503, 'NO PUEDE MODIFICAR A LOS ALUMNOS FUERA DE LA JORNADA DE TRABAJO');
        ELSIF DELETING THEN
            RAISE_APPLICATION_ERROR(-20502, 'NO PUEDE ELIMINAR VALORES DE LA TABLA FUERA DE LA JORNADA DE TRABAJO');
        END IF;
    END IF;
END;
/

--INGRESAR UN NUEVO ALUMNO 
INSERT INTO ALUMNO ( COD_ALUMNO, NUMRUT_ALUMNO, DVRUT_ALUMNO, PNOMBRE_ALUMNO, SNOMBRE_ALUMNO, APPAT_ALUMNO, APMAT_ALUMNO, BECADO, COD_CURSO
) VALUES ( 2222, '12345678', '9', 'JUAN', 'PABLO', 'PEREZ', 'GOMEZ', 'N', 223);

--ELIMINAR UN ALUMNO
DELETE FROM ALUMNO WHERE COD_ALUMNO = 2221;

--ACTUALIZAR EL NOMBRE DE UN ALUMNO
UPDATE ALUMNO SET PNOMBRE_ALUMNO = 'MARIO' WHERE COD_ALUMNO = 2221;

COMMIT;
